# 创建初始环境
create database if not exists ab_test deafault charcter set utf8mb4;
use ab_test;

# 创建原始表结果
create table cookie_cats_raw(
    userid int,
    version varchar(10),
    sum_gamerounds int,
    retention_1_raw varchar(10),
    retention_7_raw varchar(10)
);

# 加载数据
LOAD DATA LOCAL INFILE '"F:/数据/cookie_cats.csv/cookie_cats.csv"'
INTO TABLE cookie_cats_raw
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(userid, version, sum_gamerounds, retention_1_raw, retention_7_raw);

# 数据转换（False和True的转换）
create table cookie_cats as(
    select userid,version,sum_gamerounds,
        case
            when lower(trim(both '\r' from trim(retention_1_raw))) = 'false' then 0
            when lower(trim(both '\r' from trim(retention_1_raw))) = 'true' then 1
            else NULL
        end as retention_1,
        case 
            when lower(trim(both '\r' from trim(retention_7_raw))) = 'false' then 0
            when lower(trim(both '\r' from trim(retention_7_raw))) = 'true' then 1
            else NULL
        end as retention_7
    from 
        cookie_cats_raw
);

# 异常检查
select 
    count(*) as row_num,
    sum(userid is not null) as userid_num,
    sum(version is not null) as version_num,
    sum(sum_gamerounds is not null) as sum_gamerounds_num,
    sum(retention_1 is not null) as retention_1_num,
    sum(retention_7 is not null) as retention_7_num,
    max(sum_gamerounds) as max_sum_gamegrounds,
    min(sum_gamerounds) as min_sum_gamegrounds
from 
    cookie_cats;
    
# 分组查看玩家人数分布
select 
    version,
    count(userid) as user_num,
    count(userid) / sum(count(userid)) over() as user_share
from 
    cookie_cats
group by
    version
order by
    version;
    

# 分组查看留存率
select 
    version,
    sum(retention_1)/count(*) as retention_1_rate,
    sum(retention_7)/count(*) as retention_7_rate
from 
    cookie_cats
group by 
    version
order by
    version;
    
# 分组查看游戏局数
with temp1 as(
    select 
        version,
        sum_gamerounds,
        row_number() over(partition by version order by sum_gamerounds) as rn,
        count(*) over(partition by version) as n
    from 
        cookie_cats
),
temp2 as(
    select
        *,
        lead(sum_gamerounds,1) over (partition by version order by rn) as next
    from
        temp1
),
temp3 as(
    select 
        version,
        max(case
            when 10 * rn =  (n+1) 
            then sum_gamerounds
            when 10 * rn <  (n+1) and (10 * rn + 10) > (n+1) 
            then sum_gamerounds + (0.1 * (n+1) - rn) * (next - sum_gamerounds)
        end) as p10,
        max(case
            when 4 * rn = (n+1) 
            then sum_gamerounds
            when 4 * rn <  (n+1) and (4 * rn + 4) >  (n+1) 
            then sum_gamerounds + (0.25 * (n+1) - rn) * (next - sum_gamerounds)
        end) as p25,
        max(case
            when 2 * rn = (n+1) 
            then sum_gamerounds
            when 2 * rn < (n+1) and (2 * rn + 2) >  (n+1) 
            then sum_gamerounds + (0.5*(n+1) - rn) * (next - sum_gamerounds)
        end) as p50,
        max(case
            when 4 * rn =3 * (n+1) 
            then sum_gamerounds
            when 4 * rn < 3 * (n+1) and (4 * rn + 4) > 3 * (n+1) 
            then sum_gamerounds + (0.75 * (n+1) - rn) * (next - sum_gamerounds)
        end) as p75,
        max(case
            when 10 * rn =9 *  (n+1) 
            then sum_gamerounds
            when 10 * rn < 9*(n+1) and (10 * rn + 10) >  9 * (n+1) 
            then sum_gamerounds + (0.9*(n+1) - rn) * (next - sum_gamerounds)
        end) as p90,
        max(case
            when 100 * rn =  99 * (n+1) 
            then sum_gamerounds
            when 100 * rn < 99 * (n+1) and (100 * rn + 100) > 99* (n+1) 
            then sum_gamerounds  + (0.99*(n+1) - rn) * (next - sum_gamerounds)
        end) as p99
    from 
        temp2
    group by 
        version   
),
temp4 as(
    select 
        version,
        count(*) as users,
        avg(sum_gamerounds) as avg_gamerounds,
        max(sum_gamerounds) as max_gamerounds,
        min(sum_gamerounds) as min_gamerounds
    from 
        temp2
    group by version
),
temp5 as (
    select 
        x.version,
        y.users,
        x.p10,
        x.p25,
        x.p50,
        x.p75,
        x.p90,
        x.p99,
        y.avg_gamerounds,
        y.max_gamerounds,
        y.min_gamerounds
    from 
        temp3 x 
    join temp4 y on x.version = y.version
    order by version
) 
select * from temp5;
    
# 对1和7日留存率进行检验，计算差值并添加置信区间
    
with temp1 as (
    select 
        'retention_1' as metric,
        version,
        sum(retention_1) as success,
        count(*) as n
    from 
        cookie_cats
    group by 
        version 
    union all
    select 
        'retention_7' as metric,
        version,
        sum(retention_7) as success,
        count(*) as n
    from 
        cookie_cats
    group by 
        version 
    order by
        version
),
temp2 as (
    select 
        metric,
        max(case when version = 'gate_30' then success / n end )as p1,
        max(case when version = 'gate_40' then success / n end) as p2,
        max(case when version = 'gate_30' then n end )as n1,
        max(case when version = 'gate_40' then n end )as n2,
        sum(success) / sum(n) as p
    from 
        temp1
    group by 
        metric
),
temp_z as(
    select 
        metric,
        (p1 - p2) / sqrt(p * (1 - p)*((1/n1) + (1/n2))) as z,
        (p1 - p2) as diff,
        sqrt(
            p1 * (1 - p1) / n1
          + p2 * (1 - p2) / n2
        ) as se_diff
    from 
        temp2
    group by 
        metric
),
temp_normal as(
    select 
        metric,
        abs(z) as z,
        1.0 / (1.0 + 0.2316419 * abs(z)) AS x,
        diff,
        round(diff - 1.96 * se_diff, 4) as ci_lower_95,
        round(diff + 1.96 * se_diff, 4) as ci_upper_95
    from
        temp_z
),
param as (
    select
        metric,
        z,
        x,
        diff,
        ci_lower_95,
        ci_upper_95, 
        (0.319381530 * x
       - 0.356563782 * power(x,2)
       + 1.781477937 * power(x,3)
       - 1.821255978 * power(x,4)
       + 1.330274429 * power(x,5)) AS poly,
        (1.0 / sqrt(2 * pi())) * exp(-z * z / 2.0) AS phi_x
    from
        temp_normal
)

select
    metric,
    diff,
    ci_lower_95,
    ci_upper_95,
    z AS z_abs,
    2.0 * phi_x * poly AS p_value
from param;

# 检验游戏局数的分布是否相同
with temp1 as(
    select
        version,
        sum_gamerounds,
        rank() over(order by sum_gamerounds) + (count(*) over(partition by sum_gamerounds) - 1) / 2 as avg_rank
    from 
        cookie_cats
),
sum_rk as(
    select
        version,
        count(*) as n,
        sum(avg_rank) as rk_sum
    from 
        temp1
    group by 
        version
),
temp_u as(
    select 
        version,
        n,
        rk_sum,
        rk_sum - n*(n+1)/2 as U 
    from sum_rk
),
param1 as(
    select
        max(case when version = 'gate_30' then U end) as U1,
        max(case when version = 'gate_40' then U end) as U2, 
        max(case when version = 'gate_30' then n end) as n1,
        max(case when version = 'gate_40' then n end) as n2
    from 
        temp_u
),
temp_z as(
    select 
        (U1 - (n1*n2/2))/(sqrt(n1*n2*(n1+n2+ 1)/12)) as z
    from 
        param1
),
temp_normal as(
    select 
        abs(z) as z,
        1.0 / (1.0 + 0.2316419 * abs(z)) AS x
    from
        temp_z
),
param2 as (
    select
        z,
        x,
        (0.319381530 * x
       - 0.356563782 * power(x,2)
       + 1.781477937 * power(x,3)
       - 1.821255978 * power(x,4)
       + 1.330274429 * power(x,5)) AS poly,
        (1.0 / sqrt(2 * pi())) * exp(-z * z / 2.0) AS phi_x
    from
        temp_normal
)
select
    z AS z_abs,
    2.0 * phi_x * poly AS p_value
from param2;
