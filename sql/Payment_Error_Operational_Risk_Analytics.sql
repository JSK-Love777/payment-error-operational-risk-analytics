-- ============================================================
-- PAYMENT TRANSACTION ERROR & CARD REPETITION ANALYTICS
-- Portfolio-ready master SQL
-- revision: v2 - strengthened Q1/Q2 quantified insights and interview takeaways

-- database:
-- MySQL 8+

-- source tables expected:
-- raw_transactions
-- raw_users
-- raw_cards

-- analytical flow:
-- 1. clean source tables
-- 2. Q1 customer/card behavior
-- 3. Q2 payment-method behavior
-- 4. Q3 reliable high-error segment identification
-- 5. Q4 card-level error repetition
-- 6. Q5 ordinary high-error vs outlier comparison

-- design principles:
-- - final analytical tables are reusable in Excel and Power BI
-- - QA queries validate grain, reconciliation, and classifications
-- - statistical thresholds are documented and reproducible
-- - analyst-defined descriptive cutoffs are explicitly labeled
-- - unused sensitive-like fields are excluded from the analytical layer

-- public portfolio note:
-- do not commit raw source data unless the dataset license permits it.
-- document the public dataset source and limitations in the README.
-- ============================================================


-- ============================================================
-- 00-1. clean transactions
-- grain: 1 row = 1 transaction

-- purpose:
-- convert raw transaction fields into analysis-ready types and
-- create a simple amount-sign classification.
-- ============================================================

drop table if exists clean_transactions;

create table clean_transactions as
select
    id,
    str_to_date(`date`, '%Y-%m-%d %H:%i:%s') as transaction_datetime,
    client_id,
    card_id,

    cast(
        replace(replace(amount, '$', ''), ',', '')
        as decimal(15,2)
    ) as amount,

    case
        when cast(replace(replace(amount, '$', ''), ',', '') as decimal(15,2)) > 0
            then 'positive'
        when cast(replace(replace(amount, '$', ''), ',', '') as decimal(15,2)) = 0
            then 'zero'
        when cast(replace(replace(amount, '$', ''), ',', '') as decimal(15,2)) < 0
            then 'negative'
    end as amount_type,

    use_chip,
    merchant_id,
    merchant_city,
    merchant_state,
    zip,
    mcc,
    errors

from raw_transactions;


-- ============================================================
-- 00-2. clean users
-- grain: 1 row = 1 customer

-- purpose:
-- convert user attributes into analysis-ready types.
-- location/address fields are excluded because they are not used
-- in the current analytical questions.
-- ============================================================

drop table if exists clean_users;

create table clean_users as
select
    id,

    cast(current_age as unsigned) as current_age,
    cast(retirement_age as unsigned) as retirement_age,
    cast(birth_year as unsigned) as birth_year,
    cast(birth_month as unsigned) as birth_month,

    gender,

    cast(
        replace(replace(per_capita_income, '$', ''), ',', '')
        as decimal(15,2)
    ) as per_capita_income,

    cast(
        replace(replace(yearly_income, '$', ''), ',', '')
        as decimal(15,2)
    ) as yearly_income,

    cast(
        replace(replace(total_debt, '$', ''), ',', '')
        as decimal(15,2)
    ) as total_debt,

    cast(credit_score as unsigned) as credit_score,
    cast(num_credit_cards as unsigned) as num_credit_cards

from raw_users;


-- ============================================================
-- 00-3. clean cards
-- grain: 1 row = 1 card

-- purpose:
-- convert card attributes into analysis-ready types.
-- raw card number and CVV are intentionally excluded from the
-- analytical layer because they are not required for this project.
-- ============================================================

drop table if exists clean_cards;

create table clean_cards as
select
    id,
    client_id,

    card_brand,
    card_type,

    str_to_date(
        concat('01/', expires),
        '%d/%m/%Y'
    ) as expires_date,

    has_chip,

    cast(num_cards_issued as unsigned) as num_cards_issued,

    cast(
        replace(replace(credit_limit, '$', ''), ',', '')
        as decimal(15,2)
    ) as credit_limit,

    str_to_date(
        concat('01/', acct_open_date),
        '%d/%m/%Y'
    ) as acct_open_date,

    cast(year_pin_last_changed as unsigned) as year_pin_last_changed,

    card_on_dark_web

from raw_cards;





-- Q1

-- =================================================================
-- q1-1. final customer behavior
-- grain: 1 row = 1 customer (client_id)

-- purpose:
-- summarize customer-level transaction frequency, amount behavior,
-- error behavior, and unusual activity patterns.

-- downstream use:
-- excel validation / power bi visualization
-- =================================================================

drop table if exists final_q1_customer_behavior;

create table final_q1_customer_behavior as 

with customer_behavior as (

    select
        client_id,

        count(*) as transaction_count,

        sum(amount) as net_transaction_amount,

        sum(
            case
                when amount > 0 then 1
                else 0
            end
        ) as positive_transaction_count,

        sum(
            case
                when amount > 0 then amount
                else 0
            end
        ) as positive_transaction_amount,

        avg(
            case
                when amount > 0 then amount
            end
        ) as avg_positive_transaction_amount,

        sum(
            case
                when amount = 0 then 1 
                else 0
            end
        ) as zero_transaction_count, -- we don't know the reason why it has ZERO so we just remind we have ZERO amount

        sum(
            case
                when amount < 0 then 1
                else 0
            end
        ) as negative_transaction_count,

        sum(
            case
                when amount < 0 then amount
                else 0
            end
        ) as negative_transaction_amount,

        sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) as error_transaction_count

    from clean_transactions

    group by client_id
),

positive_transactions as (

    select
        client_id,
        amount,

        row_number() over (
            partition by client_id
            order by amount
        ) as rn,

        count(*) over (
            partition by client_id
        ) as positive_transaction_count

    from clean_transactions

    where amount > 0
),

customer_amount_stats as (

    select
        client_id,

        avg(
            case
                when rn in (
                    floor((positive_transaction_count + 1) / 2),
                    ceil((positive_transaction_count + 1) / 2)
                )
                then amount
            end
        ) as median_positive_transaction_amount

    from positive_transactions

    group by client_id
),

customer_enriched as (

    select
        cb.client_id,

        cb.transaction_count,

        cast(								
            cb.net_transaction_amount
            as decimal(18,2)
        ) as net_transaction_amount,

        cb.positive_transaction_count,

        cast(
            cb.positive_transaction_amount
            as decimal(18,2)
        ) as positive_transaction_amount,

        cast(
            cb.avg_positive_transaction_amount
            as decimal(18,6)
        ) as avg_positive_transaction_amount,

        cast(
            cas.median_positive_transaction_amount
            as decimal(18,6)
        ) as median_positive_transaction_amount,

        cast(
            cb.avg_positive_transaction_amount
            - cas.median_positive_transaction_amount
            as decimal(18,6)
        ) as avg_median_difference,

        cast(
            cb.avg_positive_transaction_amount
            / nullif(cas.median_positive_transaction_amount, 0)
            as decimal(18,6)
        ) as avg_median_ratio,

        cb.zero_transaction_count,

        cast(
            100.0 * cb.zero_transaction_count
            / nullif(cb.transaction_count, 0)
            as decimal(12,6)
        ) as zero_rate_pct,

        cb.negative_transaction_count,

        cast(
            cb.negative_transaction_amount
            as decimal(18,2)
        ) as negative_transaction_amount,

        cast(
            100.0 * cb.negative_transaction_count
            / nullif(cb.transaction_count, 0)
            as decimal(12,6)
        ) as negative_rate_pct,

        cb.error_transaction_count,

        cast(
            100.0 * cb.error_transaction_count
            / nullif(cb.transaction_count, 0)
            as decimal(12,6)
        ) as error_rate_pct

    from customer_behavior cb

    left join customer_amount_stats cas
        on cb.client_id = cas.client_id
),

ranked_frequency as (

    select
        client_id,
        transaction_count,

        row_number() over (
            order by transaction_count
        ) as rn,

        count(*) over () as customer_count

    from customer_enriched
),

frequency_stats as (

    select
        max(
            case
                when rn = ceil(customer_count * 0.25)
                then transaction_count
            end
        ) as q1_transaction_count,

        max(
            case
                when rn = ceil(customer_count * 0.75)
                then transaction_count
            end
        ) as q3_transaction_count,

        max(
            case
                when rn = ceil(customer_count * 0.99)
                then transaction_count
            end
        ) as p99_transaction_count

    from ranked_frequency
),

frequency_bounds as (

    select
        q3_transaction_count
        + 1.5 * (
            q3_transaction_count - q1_transaction_count
        ) as upper_bound_transaction_count,

        p99_transaction_count

    from frequency_stats
),

ranked_amount as (

    select
        client_id,
        median_positive_transaction_amount,

        row_number() over (
            order by median_positive_transaction_amount
        ) as rn,

        count(*) over () as customer_count

    from customer_enriched

    where median_positive_transaction_amount is not null
),

amount_stats as (

    select
        max(
            case
                when rn = ceil(customer_count * 0.25)
                then median_positive_transaction_amount
            end
        ) as q1_median_amount,

        max(
            case
                when rn = ceil(customer_count * 0.75)
                then median_positive_transaction_amount
            end
        ) as q3_median_amount,

        max(
            case
                when rn = ceil(customer_count * 0.99)
                then median_positive_transaction_amount
            end
        ) as p99_median_amount

    from ranked_amount
),

amount_bounds as (

    select
        q3_median_amount
        + 1.5 * (
            q3_median_amount - q1_median_amount
        ) as upper_bound_median_amount,

        p99_median_amount

    from amount_stats
),

ranked_ratio as (

    select
        client_id,
        avg_median_ratio,

        row_number() over (
            order by avg_median_ratio
        ) as rn,

        count(*) over () as customer_count

    from customer_enriched

    where avg_median_ratio is not null
),

ratio_stats as (

    select
        max(
            case
                when rn = ceil(customer_count * 0.25)
                then avg_median_ratio
            end
        ) as q1_ratio,

        max(
            case
                when rn = ceil(customer_count * 0.75)
                then avg_median_ratio
            end
        ) as q3_ratio,

        max(
            case
                when rn = ceil(customer_count * 0.99)
                then avg_median_ratio
            end
        ) as p99_ratio

    from ranked_ratio
),

ratio_bounds as (

    select
        q3_ratio
        + 1.5 * (
            q3_ratio - q1_ratio
        ) as upper_bound_ratio,

        p99_ratio

    from ratio_stats
)


select
    ce.client_id,

    ce.transaction_count,
    ce.net_transaction_amount,

    ce.positive_transaction_count,
    ce.positive_transaction_amount,
    ce.avg_positive_transaction_amount,
    ce.median_positive_transaction_amount,
    ce.avg_median_difference,
    ce.avg_median_ratio,

    ce.zero_transaction_count,
    ce.zero_rate_pct,

    ce.negative_transaction_count,
    ce.negative_transaction_amount,
    ce.negative_rate_pct,

    ce.error_transaction_count,
    ce.error_rate_pct,

    case
        when ce.transaction_count >= fb.p99_transaction_count
            then 'p99+'

        when ce.transaction_count > fb.upper_bound_transaction_count
            then 'iqr-outlier'

        else 'normal'
    end as frequency_flag,

    case
        when ce.median_positive_transaction_amount is null
            then 'not-applicable'

        when ce.median_positive_transaction_amount >= ab.p99_median_amount
            then 'p99+'

        when ce.median_positive_transaction_amount > ab.upper_bound_median_amount
            then 'iqr-outlier'

        else 'normal'
    end as amount_level_flag,

    case
        when ce.avg_median_ratio is null
            then 'not-applicable'

        when ce.avg_median_ratio >= rb.p99_ratio
            then 'p99+'

        when ce.avg_median_ratio > rb.upper_bound_ratio
            then 'iqr-outlier'

        else 'normal'
    end as ratio_flag

from customer_enriched ce

cross join frequency_bounds fb
cross join amount_bounds ab
cross join ratio_bounds rb     ;



-- ============================================================
-- q1-1. actual result check
-- ============================================================

select *
from final_q1_customer_behavior
order by transaction_count desc;



-- 1. Grain check
select
    count(*) as row_count,
    count(distinct client_id) as distinct_customer_count
from final_q1_customer_behavior;



-- 2. total transaction count = classified transaction count
select
    sum(transaction_count) as total_transaction_count,

    sum(positive_transaction_count)
    + sum(zero_transaction_count)
    + sum(negative_transaction_count)
        as classified_transaction_count

from final_q1_customer_behavior;



-- 3. clean_transactions vs final_q1_customer_behavior (count & error)
select
    (select count(*)
     from clean_transactions)
        as source_transaction_count,

    (select sum(transaction_count)
     from final_q1_customer_behavior)
        as final_transaction_count,

    (select
         sum(
             case
                 when errors is not null
                  and trim(errors) <> ''
                 then 1
                 else 0
             end
         )
     from clean_transactions)
        as source_error_count,

    (select sum(error_transaction_count)
     from final_q1_customer_behavior)
        as final_error_count;






-- ============================================================
-- q1-2. final card behavior
-- grain: 1 row = 1 card (card_id)

-- purpose:
-- summarize card-level transaction frequency, amount behavior,
-- error behavior, and unusual activity patterns.

-- downstream use:
-- excel validation / power bi visualization
-- ============================================================

drop table if exists final_q1_card_behavior;

create table final_q1_card_behavior as

with card_behavior as (

    select
        card_id,
        client_id,

        count(*) as transaction_count,

        sum(amount) as net_transaction_amount,

        sum(
            case
                when amount > 0 then 1
                else 0
            end
        ) as positive_transaction_count,

        sum(
            case
                when amount > 0 then amount
                else 0
            end
        ) as positive_transaction_amount,

        avg(
            case
                when amount > 0 then amount
            end
        ) as avg_positive_transaction_amount,

        sum(
            case
                when amount = 0 then 1
                else 0
            end
        ) as zero_transaction_count,

        sum(
            case
                when amount < 0 then 1
                else 0
            end
        ) as negative_transaction_count,

        sum(
            case
                when amount < 0 then amount
                else 0
            end
        ) as negative_transaction_amount,

        sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) as error_transaction_count

    from clean_transactions

    group by
        card_id,
        client_id
),

positive_card_transactions as (

    select
        card_id,
        client_id,
        amount,

        row_number() over (
            partition by card_id, client_id
            order by amount
        ) as rn,

        count(*) over (
            partition by card_id, client_id
        ) as positive_transaction_count

    from clean_transactions

    where amount > 0
),

card_amount_stats as (

    select
        card_id,
        client_id,

        avg(
            case
                when rn in (
                    floor((positive_transaction_count + 1) / 2),
                    ceil((positive_transaction_count + 1) / 2)
                )
                then amount
            end
        ) as median_positive_transaction_amount

    from positive_card_transactions

    group by
        card_id,
        client_id
),

card_enriched as (

    select
        cb.card_id,
        cb.client_id,

        cb.transaction_count,

        cast(
            cb.net_transaction_amount
            as decimal(18,2)
        ) as net_transaction_amount,

        cb.positive_transaction_count,

        cast(
            cb.positive_transaction_amount
            as decimal(18,2)
        ) as positive_transaction_amount,

        cast(
            cb.avg_positive_transaction_amount
            as decimal(18,6)
        ) as avg_positive_transaction_amount,

        cast(
            cas.median_positive_transaction_amount
            as decimal(18,6)
        ) as median_positive_transaction_amount,

        cast(
            cb.avg_positive_transaction_amount
            - cas.median_positive_transaction_amount
            as decimal(18,6)
        ) as avg_median_difference,

        cast(
            cb.avg_positive_transaction_amount
            / nullif(cas.median_positive_transaction_amount, 0)
            as decimal(18,6)
        ) as avg_median_ratio,

        cb.zero_transaction_count,

        cast(
            100.0 * cb.zero_transaction_count
            / nullif(cb.transaction_count, 0)
            as decimal(12,6)
        ) as zero_rate_pct,

        cb.negative_transaction_count,

        cast(
            cb.negative_transaction_amount
            as decimal(18,2)
        ) as negative_transaction_amount,

        cast(
            100.0 * cb.negative_transaction_count
            / nullif(cb.transaction_count, 0)
            as decimal(12,6)
        ) as negative_rate_pct,

        cb.error_transaction_count,

        cast(
            100.0 * cb.error_transaction_count
            / nullif(cb.transaction_count, 0)
            as decimal(12,6)
        ) as error_rate_pct

    from card_behavior cb

    left join card_amount_stats cas
        on cb.card_id = cas.card_id
       and cb.client_id = cas.client_id
),

ranked_frequency as (

    select
        card_id,
        client_id,
        transaction_count,

        row_number() over (
            order by transaction_count
        ) as rn,

        count(*) over () as card_count

    from card_enriched
),

frequency_stats as (

    select
        max(
            case
                when rn = ceil(card_count * 0.25)
                then transaction_count
            end
        ) as q1_transaction_count,

        max(
            case
                when rn = ceil(card_count * 0.75)
                then transaction_count
            end
        ) as q3_transaction_count,

        max(
            case
                when rn = ceil(card_count * 0.99)
                then transaction_count
            end
        ) as p99_transaction_count

    from ranked_frequency
),

frequency_bounds as (

    select
        q3_transaction_count
        + 1.5 * (
            q3_transaction_count - q1_transaction_count
        ) as upper_bound_transaction_count,

        p99_transaction_count

    from frequency_stats
),

ranked_amount as (

    select
        card_id,
        client_id,
        median_positive_transaction_amount,

        row_number() over (
            order by median_positive_transaction_amount
        ) as rn,

        count(*) over () as card_count

    from card_enriched

    where median_positive_transaction_amount is not null
),

amount_stats as (

    select
        max(
            case
                when rn = ceil(card_count * 0.25)
                then median_positive_transaction_amount
            end
        ) as q1_median_amount,

        max(
            case
                when rn = ceil(card_count * 0.75)
                then median_positive_transaction_amount
            end
        ) as q3_median_amount,

        max(
            case
                when rn = ceil(card_count * 0.99)
                then median_positive_transaction_amount
            end
        ) as p99_median_amount

    from ranked_amount
),

amount_bounds as (

    select
        q3_median_amount
        + 1.5 * (
            q3_median_amount - q1_median_amount
        ) as upper_bound_median_amount,

        p99_median_amount

    from amount_stats
)

select
    ce.card_id,
    ce.client_id,

    ce.transaction_count,
    ce.net_transaction_amount,

    ce.positive_transaction_count,
    ce.positive_transaction_amount,
    ce.avg_positive_transaction_amount,
    ce.median_positive_transaction_amount,
    ce.avg_median_difference,
    ce.avg_median_ratio,

    ce.zero_transaction_count,
    ce.zero_rate_pct,

    ce.negative_transaction_count,
    ce.negative_transaction_amount,
    ce.negative_rate_pct,

    ce.error_transaction_count,
    ce.error_rate_pct,

    case
        when ce.transaction_count >= fb.p99_transaction_count
            then 'p99+'

        when ce.transaction_count > fb.upper_bound_transaction_count
            then 'iqr-outlier'

        else 'normal'
    end as frequency_flag,

    case
        when ce.median_positive_transaction_amount is null
            then 'not-applicable'

        when ce.median_positive_transaction_amount >= ab.p99_median_amount
            then 'p99+'

        when ce.median_positive_transaction_amount > ab.upper_bound_median_amount
            then 'iqr-outlier'

        else 'normal'
    end as amount_level_flag

from card_enriched ce

cross join frequency_bounds fb
cross join amount_bounds ab;



-- ============================================================
-- q1-2. actual result check
-- ============================================================

select *
from final_q1_card_behavior
order by transaction_count desc;


-- 1. Grain check
select
    count(*) as row_count,
    count(distinct card_id) as distinct_card_count
from final_q1_card_behavior;


-- 2. total transaction count = classified transaction count
select
    sum(transaction_count) as total_transaction_count,

    sum(positive_transaction_count)
    + sum(zero_transaction_count)
    + sum(negative_transaction_count)
        as classified_transaction_count

from final_q1_card_behavior;


-- 3. clean_transactions vs final_q1_card_behavior (count & error)
select
    (select count(*)
     from clean_transactions)
        as source_transaction_count,

    (select sum(transaction_count)
     from final_q1_card_behavior)
        as final_transaction_count,

    (select
         sum(
             case
                 when errors is not null
                  and trim(errors) <> ''
                 then 1
                 else 0
             end
         )
     from clean_transactions)
        as source_error_count,

    (select sum(error_transaction_count)
     from final_q1_card_behavior)
        as final_error_count;









-- ============================================================
-- q1-3. Final_q1_behavior_summary
-- grain: 1 row = 1 analysis level (customer / card)

-- purpose:
-- compare customer-level and card-level transaction behavior
-- using transaction frequency, typical amount level,
-- and unusual activity patterns.

-- downstream use:
-- excel validation / power bi visualization
-- ============================================================

drop table if exists final_q1_behavior_summary;

create table final_q1_behavior_summary as

with entity_behavior as (

    select
        'Customer' as analysis_level,
        client_id as entity_id,
        transaction_count,
        median_positive_transaction_amount,
        frequency_flag,
        amount_level_flag

    from final_q1_customer_behavior

    union all

    select
        'Card' as analysis_level,
        card_id as entity_id,
        transaction_count,
        median_positive_transaction_amount,
        frequency_flag,
        amount_level_flag

    from final_q1_card_behavior
),

ranked_frequency as (

    select
        analysis_level,
        entity_id,
        transaction_count,

        row_number() over (
            partition by analysis_level
            order by transaction_count
        ) as rn,

        count(*) over (
            partition by analysis_level
        ) as entity_count

    from entity_behavior
),

frequency_stats as (

    select
        analysis_level,

        count(*) as entity_count,

        round(
            avg(transaction_count),
            2
        ) as mean_transaction_count,

        avg(
            case
                when rn in (
                    floor((entity_count + 1) / 2),
                    ceil((entity_count + 1) / 2)
                )
                then transaction_count
            end
        ) as median_transaction_count,

        max(
            case
                when rn = ceil(entity_count * 0.25)
                then transaction_count
            end
        ) as q1_transaction_count,

        max(
            case
                when rn = ceil(entity_count * 0.75)
                then transaction_count
            end
        ) as q3_transaction_count,

        max(
            case
                when rn = ceil(entity_count * 0.95)
                then transaction_count
            end
        ) as p95_transaction_count,

        max(
            case
                when rn = ceil(entity_count * 0.99)
                then transaction_count
            end
        ) as p99_transaction_count

    from ranked_frequency

    group by analysis_level
),

ranked_amount as (

    select
        analysis_level,
        entity_id,
        median_positive_transaction_amount,

        row_number() over (
            partition by analysis_level
            order by median_positive_transaction_amount
        ) as rn,

        count(*) over (
            partition by analysis_level
        ) as entity_count

    from entity_behavior

    where median_positive_transaction_amount is not null
),

amount_stats as (

    select
        analysis_level,

        avg(
            case
                when rn in (
                    floor((entity_count + 1) / 2),
                    ceil((entity_count + 1) / 2)
                )
                then median_positive_transaction_amount
            end
        ) as median_entity_amount,

        max(
            case
                when rn = ceil(entity_count * 0.25)
                then median_positive_transaction_amount
            end
        ) as q1_entity_amount,

        max(
            case
                when rn = ceil(entity_count * 0.75)
                then median_positive_transaction_amount
            end
        ) as q3_entity_amount,

        max(
            case
                when rn = ceil(entity_count * 0.95)
                then median_positive_transaction_amount
            end
        ) as p95_entity_amount,

        max(
            case
                when rn = ceil(entity_count * 0.99)
                then median_positive_transaction_amount
            end
        ) as p99_entity_amount

    from ranked_amount

    group by analysis_level
),

flag_summary as (

    select
        analysis_level,

        sum(
            case
                when frequency_flag = 'iqr-outlier'
                then 1
                else 0
            end
        ) as frequency_iqr_only_count,

        sum(
            case
                when frequency_flag = 'p99+'
                then 1
                else 0
            end
        ) as frequency_p99_count,

        sum(
            case
                when amount_level_flag = 'iqr-outlier'
                then 1
                else 0
            end
        ) as amount_iqr_only_count,

        sum(
            case
                when amount_level_flag = 'p99+'
                then 1
                else 0
            end
        ) as amount_p99_count

    from entity_behavior

    group by analysis_level

)

select
    fs.analysis_level,

    fs.entity_count,

    fs.mean_transaction_count,

    fs.median_transaction_count,

    fs.q1_transaction_count,

    fs.q3_transaction_count,

    fs.p95_transaction_count,

    fs.p99_transaction_count,

    ast.median_entity_amount,

    ast.q1_entity_amount,

    ast.q3_entity_amount,

    ast.p95_entity_amount,

    ast.p99_entity_amount,

    fl.frequency_iqr_only_count,

    round(
        100.0 * fl.frequency_iqr_only_count
        / fs.entity_count,
        4
    ) as frequency_iqr_only_share_pct,

    fl.frequency_p99_count,

    round(
        100.0 * fl.frequency_p99_count
        / fs.entity_count,
        4
    ) as frequency_p99_share_pct,

    fl.amount_iqr_only_count,

    round(
        100.0 * fl.amount_iqr_only_count
        / fs.entity_count,
        4
    ) as amount_iqr_only_share_pct,

    fl.amount_p99_count,

    round(
        100.0 * fl.amount_p99_count
        / fs.entity_count,
        4
    ) as amount_p99_share_pct

from frequency_stats fs

join amount_stats ast
    on fs.analysis_level = ast.analysis_level

join flag_summary fl
    on fs.analysis_level = fl.analysis_level;




-- ============================================================
-- q1-3. actual result check
-- ============================================================

select *
from final_q1_behavior_summary
order by
    case
        when analysis_level = 'Customer' then 1
        when analysis_level = 'Card' then 2
    end;




-- ============================================================
-- q1-3. qa: grain validation
-- ============================================================

select
    count(*) as row_count,
    count(distinct analysis_level) as distinct_analysis_level_count
from final_q1_behavior_summary;



-- ============================================================
-- q1-3. qa: entity count reconciliation
-- ============================================================

select
    s.analysis_level,
    s.entity_count,

    case
        when s.analysis_level = 'Customer'
            then (select count(*) from final_q1_customer_behavior)

        when s.analysis_level = 'Card'
            then (select count(*) from final_q1_card_behavior)
    end as source_entity_count

from final_q1_behavior_summary s
order by analysis_level desc;



-- ============================================================
-- q1-3. qa: flag sanity check
-- ============================================================

select
    analysis_level,
    entity_count,

    frequency_iqr_only_count,
    frequency_p99_count,

    amount_iqr_only_count,
    amount_p99_count

from final_q1_behavior_summary
order by analysis_level desc;




/*

[Q1 - Key Insight]

Q1 established the behavioral baseline at both customer and 
card grain and tested whether customer-level aggregation masks card-level heterogeneity.
Typical positive transaction amounts were broadly similar across the two grains: 
the median entity-level positive transaction amount was approximately 31.01 at the customer level 
and 29.74 at the card level.

However, unusual activity became more visible after decomposing customers into individual cards. 
The share of entities classified as IQR-only high-frequency cases increased from 1.89% at the customer level 
to 4.32% at the card level, while the IQR-only unusual-amount share increased from 0.57% to 1.23%.

This indicates that customer-level aggregation can smooth over concentrated card-level behavior 
even when typical transaction amounts remain similar. 
Operationally, customer-level metrics are useful for an overall behavioral baseline, 
while card-level monitoring is more appropriate for identifying localized high-frequency 
or unusual-amount patterns that may warrant further investigation.


*/












-- Q2
-- ============================================================
-- q2. final payment method behavior
-- grain: 1 row = 1 payment method (use_chip)

-- purpose:
-- compare transaction volume, transaction amount behavior,
-- and error occurrence across payment methods.

-- downstream use:
-- excel validation / power bi visualization
-- ============================================================

drop table if exists final_q2_payment_method_behavior;

create table final_q2_payment_method_behavior as

with use_chip_behavior as (

    select
        use_chip,

        count(*) as transaction_count,

        sum(
            case
                when amount > 0 then 1
                else 0
            end
        ) as positive_transaction_count,

        avg(
            case
                when amount > 0 then amount
            end
        ) as avg_positive_transaction_amount,

        sum(
            case
                when amount = 0 then 1
                else 0
            end
        ) as zero_transaction_count,

        sum(
            case
                when amount < 0 then 1
                else 0
            end
        ) as negative_transaction_count,

        sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) as error_transaction_count

    from clean_transactions

    group by use_chip
),

positive_use_chip_transactions as (

    select
        use_chip,
        amount,

        row_number() over (
            partition by use_chip
            order by amount
        ) as rn,

        count(*) over (
            partition by use_chip
        ) as positive_transaction_count

    from clean_transactions

    where amount > 0
),

use_chip_amount_stats as (

    select
        use_chip,

        avg(
            case
                when rn in (
                    floor((positive_transaction_count + 1) / 2),
                    ceil((positive_transaction_count + 1) / 2)
                )
                then amount
            end
        ) as median_positive_transaction_amount

    from positive_use_chip_transactions

    group by use_chip
)

select
    ucb.use_chip,

    ucb.transaction_count,

    round(
        100.0 * ucb.transaction_count
        / sum(ucb.transaction_count) over (),
        4
    ) as transaction_share_pct,

    ucb.positive_transaction_count,

    round(
        ucb.avg_positive_transaction_amount,
        6
    ) as avg_positive_transaction_amount,

    round(
        ucas.median_positive_transaction_amount,
        6
    ) as median_positive_transaction_amount,

    round(
        ucb.avg_positive_transaction_amount
        - ucas.median_positive_transaction_amount,
        6
    ) as avg_median_difference,

    round(
        ucb.avg_positive_transaction_amount
        / nullif(ucas.median_positive_transaction_amount, 0),
        6
    ) as avg_median_ratio,

    ucb.zero_transaction_count,

    round(
        100.0 * ucb.zero_transaction_count
        / nullif(ucb.transaction_count, 0),
        6
    ) as zero_rate_pct,

    ucb.negative_transaction_count,

    round(
        100.0 * ucb.negative_transaction_count
        / nullif(ucb.transaction_count, 0),
        6
    ) as negative_rate_pct,

    ucb.error_transaction_count,

    round(
        100.0 * ucb.error_transaction_count
        / nullif(ucb.transaction_count, 0),
        6
    ) as error_rate_pct

from use_chip_behavior ucb

join use_chip_amount_stats ucas
    on ucb.use_chip = ucas.use_chip;




-- ============================================================
-- q2. actual result check
-- ============================================================

select *
from final_q2_payment_method_behavior
order by transaction_count desc;




-- ============================================================
-- q2. qa: grain validation
-- ============================================================

select
    count(*) as row_count,
    count(distinct use_chip) as distinct_payment_method_count
from final_q2_payment_method_behavior;




-- ============================================================
-- q2. qa: transaction reconciliation
-- ============================================================

select
    (select count(*)
     from clean_transactions)
        as source_transaction_count,

    (select sum(transaction_count)
     from final_q2_payment_method_behavior)
        as final_transaction_count;




-- ============================================================
-- q2. qa: transaction share sanity check
-- ============================================================

select
    sum(transaction_share_pct) as total_transaction_share_pct
from final_q2_payment_method_behavior;







-- ============================================================
-- q2. qa: excel validation base data
-- grain: 1 row = 1 transaction month x 1 payment method
--
-- purpose:
-- creates the lower grain data needed to recalculate
-- q2 payment method metrics independently in excel.
--
-- downstream use:
-- excel cross-validation
-- ============================================================
select
    date_format(transaction_datetime, '%Y-%m') as transaction_month,
    use_chip,
    count(*) as transaction_count,

    sum(
        case
            when amount > 0 then 1
            else 0
        end
    ) as positive_transaction_count,

    sum(
        case
            when amount > 0 then amount
            else 0
        end
    ) as positive_transaction_amount,

    sum(
        case
            when amount = 0 then 1
            else 0
        end
    ) as zero_transaction_count,

    sum(
        case
            when amount < 0 then 1
            else 0
        end
    ) as negative_transaction_count,

    sum(
        case
            when errors is not null
             and trim(errors) <> ''
            then 1
            else 0
        end
    ) as error_transaction_count

from clean_transactions

group by
    date_format(transaction_datetime, '%Y-%m'),
    use_chip

order by
    transaction_month,
    use_chip;





/*

[Q2 - Key Insight]

Q2 showed that payment method is a meaningful segmentation variable for both transaction behavior 
and error occurrence. Swipe represented the majority of activity at approximately 52.36% of transactions,
followed by Chip at 35.93%, while Online accounted for only about 11.71%.

Despite its smaller transaction share, Online transactions showed higher typical positive transaction amounts 
and the highest observed error rate at approximately 2.28%. 
Swipe and Chip, in contrast, showed relatively similar amount and error patterns, 
while negative transactions were substantially less common Online.

The practical implication is that transaction volume alone does not identify the payment channel 
that deserves the most error-focused attention. 
Online activity has lower volume but a disproportionately less favorable error profile, 
so payment method should remain part of downstream error segmentation and 
Online transactions should receive targeted follow-up monitoring. 
This is an observed association, not evidence that the Online channel itself causes the errors.


*/





















-- Q3

-- ============================================================
-- q3-0. final methodology summary
-- grain: 1 row = 1 Q3 methodology configuration

-- purpose:
-- preserve the statistical screening and classification thresholds
-- used by Q3 so that QA, Excel, Power BI, GitHub documentation,
-- and interview explanations all reference the same values.

-- methodology notes:
-- - 95% confidence and +/- 1.0 percentage-point margin of error
--   are analyst-selected precision criteria for the minimum
--   transaction-count screen.
-- - the resulting minimum size is a screening threshold, not a
--   claim that every eligible segment has an exact +/- 1.0 pp CI.
-- - high-error threshold = Q3 of eligible segment error rates.
-- - outlier threshold = Q3 + 1.5 * IQR.

-- downstream use:
-- excel validation / power bi methodology cards / README
-- ============================================================

drop table if exists final_q3_methodology_summary;

create table final_q3_methodology_summary as

with methodology_parameters as (

    select
        95.0 as confidence_level_pct,
        1.96 as z_score,
        0.01 as margin_of_error

),

baseline as (

    select
        1.0 * sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) / count(*) as baseline_error_rate

    from clean_transactions

),

minimum_segment_size as (

    select
        ceil(
            power(mp.z_score, 2)
            * b.baseline_error_rate
            * (1 - b.baseline_error_rate)
            / power(mp.margin_of_error, 2)
        ) as minimum_transaction_count

    from methodology_parameters mp

    cross join baseline b

),

error_concentration as (

    select
        mcc,
        hour(transaction_datetime) as hour_of_day,
        use_chip,

        count(*) as transaction_count,

        sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) as error_transaction_count,

        100.0 * sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) / count(*) as error_rate_pct

    from clean_transactions

    group by
        mcc,
        hour(transaction_datetime),
        use_chip

),

eligible_segments as (

    select
        ec.*

    from error_concentration ec

    cross join minimum_segment_size mss

    where ec.transaction_count >= mss.minimum_transaction_count

),

ranked_eligible_segments as (

    select
        es.*,

        row_number() over (
            order by error_rate_pct
        ) as rn,

        count(*) over () as eligible_segment_count

    from eligible_segments es

),

error_rate_stats as (

    select
        avg(
            case
                when rn in (
                    floor((eligible_segment_count + 1) * 0.25),
                    ceil((eligible_segment_count + 1) * 0.25)
                )
                then error_rate_pct
            end
        ) as q1_error_rate_pct,

        avg(
            case
                when rn in (
                    floor((eligible_segment_count + 1) * 0.50),
                    ceil((eligible_segment_count + 1) * 0.50)
                )
                then error_rate_pct
            end
        ) as median_error_rate_pct,

        avg(
            case
                when rn in (
                    floor((eligible_segment_count + 1) * 0.75),
                    ceil((eligible_segment_count + 1) * 0.75)
                )
                then error_rate_pct
            end
        ) as q3_error_rate_pct

    from ranked_eligible_segments

)

select
    round(
        100.0 * b.baseline_error_rate,
        4
    ) as baseline_error_rate_pct,

    mp.confidence_level_pct,
    mp.z_score,

    round(
        100.0 * mp.margin_of_error,
        2
    ) as margin_of_error_pct,

    mss.minimum_transaction_count,

    round(
        ers.q1_error_rate_pct,
        4
    ) as eligible_q1_error_rate_pct,

    round(
        ers.median_error_rate_pct,
        4
    ) as eligible_median_error_rate_pct,

    round(
        ers.q3_error_rate_pct,
        4
    ) as high_error_threshold_pct,

    round(
        ers.q3_error_rate_pct - ers.q1_error_rate_pct,
        4
    ) as eligible_iqr_error_rate_pct,

    round(
        ers.q3_error_rate_pct
        + 1.5 * (ers.q3_error_rate_pct - ers.q1_error_rate_pct),
        4
    ) as outlier_upper_bound_error_rate_pct

from methodology_parameters mp

cross join baseline b
cross join minimum_segment_size mss
cross join error_rate_stats ers;


-- ============================================================
-- q3-0. actual methodology check
-- ============================================================

select *
from final_q3_methodology_summary;


-- ============================================================
-- q3-0. qa: methodology sanity check
-- grain: 1 row = 1 invalid methodology configuration

-- expected result:
-- 0 rows
-- ============================================================

select *
from final_q3_methodology_summary

where
       baseline_error_rate_pct < 0
    or baseline_error_rate_pct > 100
    or minimum_transaction_count <= 0
    or eligible_q1_error_rate_pct > eligible_median_error_rate_pct
    or eligible_median_error_rate_pct > high_error_threshold_pct
    or high_error_threshold_pct > outlier_upper_bound_error_rate_pct;


-- ============================================================
-- q3-1. final error concentration
-- grain: 1 row = 1 high-error-flagged
--        MCC x hour_of_day x use_chip segment, including outliers

-- purpose:
-- identify recurring error concentration patterns across
-- MCC, hour of day, and payment method after applying a
-- reproducible minimum segment-size screen.

-- downstream use:
-- excel validation / power bi visualization / GitHub results
-- ============================================================

drop table if exists final_q3_error_concentration;

create table final_q3_error_concentration as

with error_concentration as (

    select
        mcc,
        hour(transaction_datetime) as hour_of_day,
        use_chip,

        count(*) as transaction_count,

        sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) as error_transaction_count,

        100.0 * sum(
            case
                when errors is not null
                 and trim(errors) <> ''
                then 1
                else 0
            end
        ) / count(*) as error_rate_pct

    from clean_transactions

    group by
        mcc,
        hour(transaction_datetime),
        use_chip

),

eligible_segments as (

    select
        ec.*

    from error_concentration ec

    cross join final_q3_methodology_summary m

    where ec.transaction_count >= m.minimum_transaction_count

),

classified_segments as (

    select
        es.*,

        case
            when es.error_rate_pct >= m.high_error_threshold_pct
            then 1
            else 0
        end as high_error_flag,

        case
            when es.error_rate_pct > m.outlier_upper_bound_error_rate_pct
            then 1
            else 0
        end as outlier_flag,

        case
            when es.error_rate_pct > m.outlier_upper_bound_error_rate_pct
            then 'outlier'

            when es.error_rate_pct >= m.high_error_threshold_pct
            then 'high-error'

            else 'normal'
        end as error_level

    from eligible_segments es

    cross join final_q3_methodology_summary m

),

mcc_summary as (

    select
        mcc,

        sum(high_error_flag) as high_error_segment_count,

        sum(outlier_flag) as outlier_segment_count,

        avg(error_rate_pct)
            as mcc_avg_eligible_segment_error_rate_pct

    from classified_segments

    group by mcc

    having sum(high_error_flag) >= 2

)

select
    cs.mcc,
    ms.high_error_segment_count,
    ms.outlier_segment_count,

    round(
        ms.mcc_avg_eligible_segment_error_rate_pct,
        4
    ) as mcc_avg_eligible_segment_error_rate_pct,

    cs.hour_of_day,
    cs.use_chip,
    cs.transaction_count,
    cs.error_transaction_count,

    round(
        cs.error_rate_pct,
        4
    ) as error_rate_pct,

    cs.error_level

from classified_segments cs

join mcc_summary ms
    on cs.mcc = ms.mcc

where cs.high_error_flag = 1;


-- ============================================================
-- q3-1. actual result check
-- ============================================================

select *
from final_q3_error_concentration
order by
    high_error_segment_count desc,
    mcc,
    error_rate_pct desc;


-- ============================================================
-- q3-1. qa: grain validation
-- grain: 1 row = 1 duplicated final segment

-- expected result:
-- 0 rows
-- ============================================================

select
    mcc,
    hour_of_day,
    use_chip,
    count(*) as duplicate_count

from final_q3_error_concentration

group by
    mcc,
    hour_of_day,
    use_chip

having count(*) > 1;


-- ============================================================
-- q3-1. qa: screening condition validation
-- purpose:
-- verify that every final segment satisfies the methodology
-- stored in final_q3_methodology_summary.

-- expected result:
-- all invalid counts = 0
-- ============================================================

select
    count(*) as total_segment_count,

    sum(
        case
            when q3.transaction_count < m.minimum_transaction_count
            then 1
            else 0
        end
    ) as below_minimum_segment_size_count,

    sum(
        case
            when q3.error_rate_pct < m.high_error_threshold_pct
            then 1
            else 0
        end
    ) as below_high_error_threshold_count,

    sum(
        case
            when q3.high_error_segment_count < 2
            then 1
            else 0
        end
    ) as below_recurring_mcc_threshold_count

from final_q3_error_concentration q3

cross join final_q3_methodology_summary m;


-- ============================================================
-- q3-1. qa: MCC summary reconciliation
-- grain: 1 row = 1 MCC with a reconciliation mismatch

-- expected result:
-- 0 rows
-- ============================================================

select
    mcc,
    count(*) as actual_high_error_segment_count,
    max(high_error_segment_count) as reported_high_error_segment_count,

    sum(
        case
            when error_level = 'outlier'
            then 1
            else 0
        end
    ) as actual_outlier_segment_count,

    max(outlier_segment_count) as reported_outlier_segment_count

from final_q3_error_concentration

group by mcc

having
       count(*) <> max(high_error_segment_count)
    or sum(
        case
            when error_level = 'outlier'
            then 1
            else 0
        end
    ) <> max(outlier_segment_count);


-- ============================================================
-- q3-1. qa: error-level validation
-- grain: 1 row = 1 invalid segment

-- expected result:
-- 0 rows
-- ============================================================

select
    q3.mcc,
    q3.hour_of_day,
    q3.use_chip,
    q3.error_rate_pct,
    q3.error_level

from final_q3_error_concentration q3

cross join final_q3_methodology_summary m

where
       (
           q3.error_level = 'high-error'
           and (
                  q3.error_rate_pct < m.high_error_threshold_pct
               or q3.error_rate_pct > m.outlier_upper_bound_error_rate_pct
           )
       )

    or (
           q3.error_level = 'outlier'
           and q3.error_rate_pct <= m.outlier_upper_bound_error_rate_pct
       )

    or q3.error_level not in ('high-error', 'outlier');




-- ============================================================
-- q3-1. key insight summary
-- grain: 1 row = 1 recurring high-error MCC

-- purpose:
-- summarize recurring high-error MCCs before writing
-- the final Q3 insight.
-- ============================================================

select
    mcc,
    max(high_error_segment_count) as high_error_segment_count,
    max(outlier_segment_count) as outlier_segment_count,
    max(mcc_avg_eligible_segment_error_rate_pct)
        as mcc_avg_eligible_segment_error_rate_pct,
    max(error_rate_pct) as max_segment_error_rate_pct

from final_q3_error_concentration

group by mcc

order by
    high_error_segment_count desc,
    outlier_segment_count desc,
    max_segment_error_rate_pct desc;


/*
[Q3 - Key Insight]

After excluding low-volume segments with the reproducible minimum
transaction-count screen, Q3 identified recurring high-error patterns
at the MCC x hour-of-day x payment-method grain.

MCC 4900 stood out with 50 high-error-flagged segments across multiple
hour/payment-method combinations, including 2 statistical outliers.
This indicates that elevated error activity for this MCC was recurring
across multiple operating conditions rather than being isolated to a
single hour or payment method.

Operationally, MCCs with repeated high-error segments are stronger
candidates for follow-up investigation because the pattern persists
across multiple conditions. This is an investigation-priority signal,
not evidence that the MCC itself caused the errors.
*/






# [For Excel]
-- ============================================================
-- q3. qa: excel validation base data
-- grain: 1 row = 1 mcc x hour x payment method
--
-- purpose:
-- provides only the segment-level base counts required for
-- q3 logic to be independently reconstructed in excel.
--
-- downstream use:
-- excel cross-validation
-- ============================================================

select
    mcc,
    hour(transaction_datetime) as hour_of_day,
    use_chip,
    count(*) as transaction_count,
    sum(
        case
            when errors is not null
             and trim(errors) <> ''
            then 1
            else 0
        end
    ) as error_transaction_count

from clean_transactions

group by
    mcc,
    hour(transaction_datetime),
    use_chip

order by
    mcc,
    hour_of_day,
    use_chip;













-- Q4
-- ============================================================
-- q4. card-level error repetition base
-- grain: 1 row = 1 high-error-flagged MCC x hour_of_day x use_chip x card_id

-- purpose:
-- count how many error transactions each card generated
-- within each Q3 high-error-flagged segment, including outliers.

-- downstream use:
-- build segment-level card repetition metrics
-- ============================================================

-- ============================================================
-- q4. final error card repetition
-- grain: 1 row = 1 high-error-flagged MCC x hour_of_day x use_chip segment

-- purpose:
-- determine whether error transactions within each Q3
-- high-error-flagged segment are dispersed across many cards or
-- repeatedly concentrated on a smaller set of cards.

-- downstream use:
-- excel validation / power bi visualization
-- ============================================================

drop table if exists final_q4_error_card_repetition;

create table final_q4_error_card_repetition as

with card_error_counts as (

    select
        q3.mcc,
        q3.hour_of_day,
        q3.use_chip,
        q3.error_level,

        ct.card_id,

        count(*) as card_error_count

    from final_q3_error_concentration q3

    join clean_transactions ct
        on ct.mcc = q3.mcc
       and hour(ct.transaction_datetime) = q3.hour_of_day
       and ct.use_chip = q3.use_chip

    where ct.errors is not null
      and trim(ct.errors) <> ''

    group by
        q3.mcc,
        q3.hour_of_day,
        q3.use_chip,
        q3.error_level,
        ct.card_id

),

segment_card_repetition as (

    select
        mcc,
        hour_of_day,
        use_chip,
        error_level,

        count(*) as error_card_count,

        sum(card_error_count) as error_transaction_count,

        sum(
            case
                when card_error_count = 1
                then 1
                else 0
            end
        ) as single_error_card_count,

        sum(
            case
                when card_error_count >= 2
                then 1
                else 0
            end
        ) as repeat_error_card_count,

        avg(card_error_count) as avg_errors_per_error_card,

        100.0 * sum(
            case
                when card_error_count >= 2
                then 1
                else 0
            end
        ) / count(*) as repeat_error_card_share_pct,

        max(card_error_count) as max_card_error_count,

        100.0
            * max(card_error_count)
            / sum(card_error_count) as top_card_error_share_pct

    from card_error_counts

    group by
        mcc,
        hour_of_day,
        use_chip,
        error_level

)

select
    q3.mcc,
    q3.high_error_segment_count,
    q3.outlier_segment_count,
    q3.mcc_avg_eligible_segment_error_rate_pct,

    q3.hour_of_day,
    q3.use_chip,

    q3.transaction_count,
    q3.error_transaction_count,
    q3.error_rate_pct,
    q3.error_level,

    scr.error_card_count,
    scr.single_error_card_count,
    scr.repeat_error_card_count,

    round(
        scr.avg_errors_per_error_card,
        4
    ) as avg_errors_per_error_card,

    round(
        scr.repeat_error_card_share_pct,
        4
    ) as repeat_error_card_share_pct,

    scr.max_card_error_count,

    round(
        scr.top_card_error_share_pct,
        4
    ) as top_card_error_share_pct,

    -- analyst-defined descriptive thresholds for segment profiling;
    -- these are not statistically estimated risk cutoffs.
    case
        when scr.avg_errors_per_error_card < 1.5
        then 'low-repeat'

        when scr.avg_errors_per_error_card < 2.0
        then 'mixed'

        else 'repeat-concentrated'
    end as card_repetition_level

from final_q3_error_concentration q3

join segment_card_repetition scr
    on q3.mcc = scr.mcc
   and q3.hour_of_day = scr.hour_of_day
   and q3.use_chip = scr.use_chip
   and q3.error_level = scr.error_level;



-- ============================================================
-- q4. actual result check
-- ============================================================

select *
from final_q4_error_card_repetition
order by
    avg_errors_per_error_card desc,
    repeat_error_card_share_pct desc,
    top_card_error_share_pct desc;







-- ============================================================
-- q4. qa: error count reconciliation
-- grain: 1 row = 1 segment with an error-count mismatch

-- purpose:
-- verify that Q4 card-level aggregation preserves the
-- original Q3 error transaction count for each segment.

-- expected result:
-- 0 rows
-- ============================================================

select
    q3.mcc,
    q3.hour_of_day,
    q3.use_chip,

    q3.error_transaction_count as q3_error_transaction_count,
    q4.error_transaction_count as q4_error_transaction_count

from final_q3_error_concentration q3

join final_q4_error_card_repetition q4
    on q3.mcc = q4.mcc
   and q3.hour_of_day = q4.hour_of_day
   and q3.use_chip = q4.use_chip

where q3.error_transaction_count
   <> q4.error_transaction_count;






-- ============================================================
-- q4. qa: card count reconciliation
-- grain: 1 row = 1 segment with a card-count mismatch

-- purpose:
-- verify that every error_card is classified as either
-- single_error or repeat_error within each segment.

-- expected result:
-- 0 rows
-- ============================================================

select
    mcc,
    hour_of_day,
    use_chip,

    error_card_count,
    single_error_card_count,
    repeat_error_card_count

from final_q4_error_card_repetition

where error_card_count
   <> single_error_card_count + repeat_error_card_count;






-- ============================================================
-- q4. qa: repetition metric validation
-- grain: 1 row = 1 segment with a metric mismatch

-- purpose:
-- verify that average and share metrics are mathematically
-- consistent with their underlying counts.

-- expected result:
-- 0 rows
-- ============================================================

select
    mcc,
    hour_of_day,
    use_chip,

    error_transaction_count,
    error_card_count,
    avg_errors_per_error_card,

    repeat_error_card_count,
    repeat_error_card_share_pct,

    max_card_error_count,
    top_card_error_share_pct

from final_q4_error_card_repetition

where
       abs(
           avg_errors_per_error_card
           - (1.0 * error_transaction_count / error_card_count)
       ) > 0.0001

    or abs(
           repeat_error_card_share_pct
           - (100.0 * repeat_error_card_count / error_card_count)
       ) > 0.0001

    or abs(
           top_card_error_share_pct
           - (100.0 * max_card_error_count / error_transaction_count)
       ) > 0.0001;







-- ============================================================
-- q4. qa: card repetition level validation
-- grain: 1 row = 1 segment with an invalid classification

-- purpose:
-- verify that card repetition levels are consistent
-- with avg_errors_per_error_card thresholds.

-- expected result:
-- 0 rows
-- ============================================================

select
    mcc,
    hour_of_day,
    use_chip,
    avg_errors_per_error_card,
    card_repetition_level

from final_q4_error_card_repetition

where
       (
           card_repetition_level = 'low-repeat'
           and avg_errors_per_error_card >= 1.5
       )

    or (
           card_repetition_level = 'mixed'
           and (
                  avg_errors_per_error_card < 1.5
               or avg_errors_per_error_card >= 2.0
           )
       )

    or (
           card_repetition_level = 'repeat-concentrated'
           and avg_errors_per_error_card < 2.0
       )

    or card_repetition_level not in (
        'low-repeat',
        'mixed',
        'repeat-concentrated'
    );









-- ============================================================
-- q4. key insight summary
-- grain: 1 row = 1 card repetition level

-- purpose:
-- summarize how Q3 high-error segments are distributed
-- across card repetition patterns.
-- ============================================================

select
    card_repetition_level,

    count(*) as segment_count,

    round(
        100.0 * count(*) / sum(count(*)) over (),
        2
    ) as segment_share_pct,

    round(
        avg(avg_errors_per_error_card),
        4
    ) as avg_errors_per_error_card,

    round(
        avg(repeat_error_card_share_pct),
        4
    ) as avg_repeat_error_card_share_pct,

    round(
        avg(top_card_error_share_pct),
        4
    ) as avg_top_card_error_share_pct

from final_q4_error_card_repetition

group by card_repetition_level

order by segment_count desc;




-- [Q4 - Key Insight]
/*

Q4 examined whether the elevated error rates identified in Q3 were driven by repeated errors
on the same cards or by errors distributed across many different cards. 
Segments were classified based on the average number of errors per error-generating card: 
below 1.5 as low-repeat, 1.5 to below 2.0 as mixed, and 2.0 or higher as repeat-concentrated.

Among the 391 high-error-flagged segments, including outliers, 57.54% were low-repeat, 16.88% were mixed, and 25.58% were repeat-concentrated.
In low-repeat segments, only 18.43% of error-generating cards recorded two or more errors on average, 
meaning that approximately 81.57% recorded only a single error. 
The top error-generating card also accounted for only 8.15% of segment errors on average.
This indicates that elevated error rates in most low-repeat segments were broadly distributed 
across many different cards rather than being driven by repeated failures on a small number of cards.

For these dispersed-error segments, follow-up investigation may therefore be more useful 
at the shared segment or processing-condition level—such as MCC, time of day, payment method, 
or other transaction-processing factors—rather than focusing only on individual cards. 
This should be treated as an investigation priority rather than evidence of causation.

In contrast, repeat-concentrated segments showed substantially stronger card-level repetition: 
50.39% of error-generating cards recorded two or more errors on average. 
The top error-generating card also accounted for 24.66% of segment errors on average, 
compared with 8.15% in low-repeat segments. 
This indicates that repeated errors affected a substantial portion of cards 
while additional concentration was also present on certain individual cards.
Cards with particularly high repeated-error counts within these segments
may therefore warrant prioritized investigation and monitoring.

Overall, high-error-flagged segments did not share a single card-level error structure. 
Dispersed errors were more common overall, 
while roughly one quarter of segments exhibited strong card-level repetition. 
This suggests that follow-up investigation should be differentiated by pattern:
shared segment or processing conditions for dispersed-error segments,
and repeatedly failing cards for repetition-concentrated segments.

In practice, low-repeat segments are better candidates for investigating
shared MCC, time-of-day, payment-method, or processing conditions,
whereas repeat-concentrated segments support prioritizing cards with
the highest repeated-error counts for deeper review.


*/







# [For Excel]
-- ============================================================
-- q4. qa: excel validation base data
-- grain: 1 row = 1 high-error-flagged
--        mcc x hour_of_day x use_chip x card_id
--
-- purpose:
-- provide card-level error counts so q4 repetition metrics
-- can be independently reconstructed in excel.
--
-- downstream use:
-- excel cross-validation
-- ============================================================

select
    q3.mcc,
    q3.hour_of_day,
    q3.use_chip,
    q3.error_level,
    ct.card_id,
    count(*) as card_error_count

from final_q3_error_concentration q3

join clean_transactions ct
    on ct.mcc = q3.mcc
   and hour(ct.transaction_datetime) = q3.hour_of_day
   and ct.use_chip = q3.use_chip

where ct.errors is not null
  and trim(ct.errors) <> ''

group by
    q3.mcc,
    q3.hour_of_day,
    q3.use_chip,
    q3.error_level,
    ct.card_id

order by
    q3.mcc,
    q3.hour_of_day,
    q3.use_chip,
    card_error_count desc;


























-- Q5

-- ============================================================
-- q5-1. final error repetition comparison
-- grain: 1 row = 1 error level x 1 card repetition level

-- purpose:
-- compare card-level error repetition patterns between
-- ordinary high-error segments and outlier segments.

-- interpretation notes:
-- - error_level = 'high-error' excludes outliers.
-- - error_level = 'outlier' is mutually exclusive from ordinary high-error.
-- - avg_* metrics are unweighted averages across segment-level metrics,
--   so each segment contributes equally to the comparison.

-- downstream use:
-- excel validation / power bi visualization
-- ============================================================

drop table if exists final_q5_error_repetition_comparison;

create table final_q5_error_repetition_comparison as

with repetition_summary as (
    select
        error_level,
        card_repetition_level,
        count(*) as segment_count,
        avg(avg_errors_per_error_card) as avg_errors_per_error_card,
        avg(repeat_error_card_share_pct) as avg_repeat_error_card_share_pct,
        avg(top_card_error_share_pct) as avg_top_card_error_share_pct
    from final_q4_error_card_repetition
    group by
        error_level,			-- for ordinary high-error VS outlier
        card_repetition_level
)

select
    error_level,
    card_repetition_level,
    segment_count,

    round(
        100.0 * segment_count
        / sum(segment_count) over (
            partition by error_level
        ),
        2
    ) as within_error_level_share_pct,

    round(avg_errors_per_error_card, 4)
        as avg_errors_per_error_card,

    round(avg_repeat_error_card_share_pct, 4)
        as avg_repeat_error_card_share_pct,

    round(avg_top_card_error_share_pct, 4)
        as avg_top_card_error_share_pct

from repetition_summary;








-- ============================================================
-- q5-2. actual result check
-- ============================================================

select
    *
from final_q5_error_repetition_comparison
order by
    case error_level
        when 'high-error' then 1
        when 'outlier' then 2
        else 3
    end,
    case card_repetition_level
        when 'low-repeat' then 1
        when 'mixed' then 2
        when 'repeat-concentrated' then 3
        else 4
    end;






-- ============================================================
-- q5 qa 1. total segment reconciliation
-- ============================================================

select
    (select count(*)
     from final_q4_error_card_repetition) as q4_segment_count,

    (select sum(segment_count)
     from final_q5_error_repetition_comparison) as q5_segment_count;






-- ============================================================
-- q5 qa 2. within-level share validation
-- ============================================================

select
    error_level,
    sum(segment_count) as segment_count,
    round(sum(within_error_level_share_pct), 2) as share_sum_pct
from final_q5_error_repetition_comparison
group by error_level;






-- ============================================================
-- q5 qa 3. grain validation
-- ============================================================

select
    error_level,
    card_repetition_level,
    count(*) as row_count
from final_q5_error_repetition_comparison
group by
    error_level,
    card_repetition_level
having count(*) > 1;






-- [Q5 - Key Insight]
/*

Q5 separated the 391 high-error-flagged segments into ordinary high-error and outlier segments 
to compare their card-level repetition structures. 
Among ordinary high-error segments, low-repeat was the dominant pattern at 63.04%, 
while only 21.78% were repeat-concentrated. In contrast, only 11.90% of outlier segments were low-repeat, 
while 57.14% were repeat-concentrated. 
This shows that extreme error-rate segments were much more frequently associated with strong card-level repetition 
than ordinary high-error segments.

Within repeat-concentrated segments, the share of error-generating cards with two or more errors was nearly identical 
between ordinary high-error and outlier segments, at 50.27% and 50.75%, respectively. 
However, the average number of errors per error-generating card increased from 3.97 to 6.88, 
while the average top-card error share increased from 21.27% to 35.41%. 
This suggests that the stronger repetition observed in outlier segments was not primarily driven by 
a larger proportion of repeat-error cards, 
but by greater repetition intensity among those cards and stronger concentration on individual cards.

Operationally, outlier segments that are also repeat-concentrated can therefore be prioritized for deeper investigation, 
particularly by identifying cards with unusually high repeated-error counts or large shares of segment errors. 
These patterns should be treated as investigation signals rather than evidence 
that the identified cards caused the elevated error rates.

 */






















-- ============================================================
-- PROJECT LIMITATIONS / INTERPRETATION GUARDRAILS
--
-- 1. this project is descriptive and diagnostic; observed
--    associations do not establish causation.
--
-- 2. an error transaction is defined by a non-null, non-blank
--    errors field. error type and severity are not modeled here.
--
-- 3. the Q3 minimum-size rule is a precision-oriented screening
--    criterion derived from the observed baseline error rate,
--    95% confidence, and an analyst-selected +/- 1.0 pp margin.
--
-- 4. Q4 repetition levels (<1.5, 1.5-<2.0, >=2.0 errors per
--    error-generating card) are analyst-defined descriptive
--    categories, not statistically estimated risk thresholds.
--
-- 5. Q5 compares ordinary high-error and outlier segment
--    structures descriptively. no causal or statistical-significance
--    claim is made from the group differences alone.
--
-- 6. Q5 avg_* metrics are unweighted averages of segment-level
--    metrics, intentionally giving each segment equal influence.
--
-- 7. current Q1-Q5 analyses are transaction-centered. cleaned user
--    and card tables are retained for reproducible data preparation
--    and future enrichment but are not required by every final query.
-- ============================================================


-- ============================================================
-- DOWNSTREAM / PORTFOLIO OUTPUT MAP

-- Excel cross-validation:
-- final_q1_behavior_summary
-- final_q2_payment_method_behavior
-- final_q3_methodology_summary
-- final_q3_error_concentration
-- final_q4_error_card_repetition
-- final_q5_error_repetition_comparison

-- Power BI:
-- summary visuals:
--   final_q1_behavior_summary
--   final_q2_payment_method_behavior
--   final_q5_error_repetition_comparison

-- drill-down / diagnostic visuals:
--   final_q3_error_concentration
--   final_q4_error_card_repetition

-- detailed entity-level support:
--   final_q1_customer_behavior
--   final_q1_card_behavior

-- GitHub / README evidence:
-- methodology:
--   final_q3_methodology_summary
-- analytical results:
--   Q1-Q5 final tables and key-insight summaries
-- data quality:
--   QA queries embedded after each final analytical table

-- interview defense:
-- be prepared to explain grain, denominator choice, percentile/IQR
-- methodology, the 601 minimum-size screen, the difference between
-- high-error-flagged vs ordinary high-error, and the analyst-defined
-- Q4 repetition thresholds.
-- ============================================================
