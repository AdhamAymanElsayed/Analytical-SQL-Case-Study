-- Question one:

---- Top Selling Products   

select stockcode , "Total Quantity Sold"   
from (
        select stockcode , "Total Quantity Sold" , rank() over(order by "Total Quantity Sold" desc) as top
        from (
                select distinct stockcode , sum(quantity) over(partition by stockcode) "Total Quantity Sold"                 
                from tableretail))  
where top <= 10 ; 

---------------------------------------------------------------------------------------------------------------------------
---- Seasonal Sales Analysis

select season , round(avg("Seasonal Sales"),1) as "Seasonal Sales" 
from (
        select season , sum(quantity * price) over(partition by season) as "Seasonal Sales"
        from(
                select quantity , price ,  
                case
                    when to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'mm') in (12,1,2) then 'Winter'
                    when to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'mm') in (3,4,5) then 'Spring'
                    when to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'mm') in (6,7,8) then 'Summer'
                    else 'Fall'
                    end as season 
                
                from tableretail))
group by season 
order by "Seasonal Sales" desc; 

-----------------------------------------------------------------------------------------------------------------------------
---- Monthly Growth Rate

with monthly_sales as (
select
        to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'yyyy') as Year , 
        to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'mm') as Month,
        sum(quantity * price) as Sales
        from tableretail 
 group by  to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'yyyy') , to_char(to_date(invoicedate ,'mm/dd/yyyy HH24:MI'), 'mm')
                    ) ,
per_month_sales as (
select year , month , sales ,
        lag(sales) over (order by year , month) as previous_sales
from monthly_sales
)
select year , month , sales , round((sales - previous_sales) / previous_sales * 100 , 2) as "Growth_rate %"
from per_month_sales ;

-----------------------------------------------------------------------------------------------------------------------------
---- Customer Lifetime Value

select distinct customer_id , round(total_amount / nullif((last_date - first_date),0) ,  2) as CLV
from( 
        select customer_id , sum(price*quantity) over(partition by customer_id) as total_amount , 
            last_value (to_date(invoicedate,'mm/dd/yyyy HH24:MI')) 
            over (partition by customer_id order by to_date(invoicedate,'mm/dd/yyyy HH24:MI') range between unbounded preceding and unbounded following) as last_date , 
            first_value (to_date(invoicedate,'mm/dd/yyyy HH24:MI')) 
            over (partition by customer_id order by to_date(invoicedate,'mm/dd/yyyy HH24:MI')) as first_date
        from tableretail) ; 
              
-----------------------------------------------------------------------------------------------------------------------
---- Top 10 customers
with top_cust as(
        select distinct customer_id , sum(quantity * price) over(partition by customer_id ) as total_amount , 
        count(invoice) over(partition by customer_id) as total_transactions 
        from tableretail ) 
select customer_id , total_amount  ,  total_transactions 
from  ( 
        select customer_id , total_amount , total_transactions , row_number() over(order by total_amount desc) as rank
        from top_cust) 
where rank <= 10 ; 

----------------------------------------------------------------------------------------------------------------------
---- Churn Rate
with cust_dur as (
select count(customer_ID) as Churned_Cust
from (
        select customer_id , trunc(months / 30 ) as duration 
        from (
                select distinct customer_id ,
                (last_value (to_date(invoicedate,'mm/dd/yyyy HH24:MI')) 
                over (order by to_date(invoicedate,'mm/dd/yyyy HH24:MI') range between unbounded preceding and unbounded following) 
                - 
                last_value (to_date(invoicedate,'mm/dd/yyyy HH24:MI')) 
                over (partition by customer_id order by to_date(invoicedate,'mm/dd/yyyy HH24:MI') range between unbounded preceding and unbounded following)) as Months
                from tableretail)
        where months / 30 >=6 )
),
total_cust as (
select count(distinct customer_id) as Total_Cust 
from tableretail 
)

select Total_Cust, Churned_Cust ,round((Churned_Cust / Total_Cust )*100, 2 ) || ' %'  "churn Rate %"
from cust_dur , total_cust ;

----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question Two: 

with rfm as(
select customer_id , recency , frequancy , monetary , R_score , trunc((F_score + M_score)/2) as FM_Score
from
    ( 
    select customer_id , recency , frequancy , monetary , ntile (5) over (order by recency desc) as R_score , 
    ntile(5) over(order by  Frequancy desc) as F_score , ntile(5) over(order by  monetary desc) as M_score
    from (
        select distinct customer_id , 
            trunc(last_value (to_date(invoicedate,'mm/dd/yyyy HH24:MI')) 
            over (order by to_date(invoicedate,'mm/dd/yyyy HH24:MI') range between unbounded preceding and unbounded following) 
             - 
            last_value (to_date(invoicedate,'mm/dd/yyyy HH24:MI')) 
            over (partition by customer_id order by to_date(invoicedate,'mm/dd/yyyy HH24:MI') range between unbounded preceding and unbounded following)) as Recency ,
            count(distinct invoice) over(partition by customer_id  ) as Frequancy ,
            round((sum(quantity * price) over(partition by customer_id)) / 1000 , 2) as Monetary 
            from tableretail )) 
 order by customer_id  )
select customer_id , recency , frequancy , monetary , R_score ,FM_Score , 
case 
            when R_Score = 5 and FM_Score in (5, 4) then 'Champions'
            when R_Score = 4 and FM_Score = 5 then 'Champions'
            when R_Score = 5 and FM_Score = 2 then 'Potential Loyalists'
            when R_Score = 4 and FM_Score in (2 , 3) then 'Potential Loyalists'
            when R_Score = 3 and FM_Score = 3 then 'Potential Loyalists'
            when R_Score = 5 and FM_Score = 3 then 'Loyal Customers'
            when R_Score = 4 and FM_Score = 4 then 'Loyal Customers'
            when R_Score = 3 and FM_Score in (4 , 5) then 'Loyal Customers'
            when R_Score = 5 and FM_Score = 1 then 'Recent Customers'
            when R_Score = 4 and FM_Score = 1 then 'Promising'
            when R_Score = 3 and FM_Score = 1 then 'Promising'
            when R_Score = 3 and FM_Score = 2 then 'Customers Needing Attention'
            when R_Score = 2 and FM_Score in (2, 3) then 'Customers Needing Attention'
            when R_Score = 1 and FM_Score = 3 then 'At Risk'
            when R_Score = 2 and FM_Score in (4, 5) then 'At Risk'
            when R_Score = 1 and FM_Score = 2 then 'Hibernating'
            when R_Score = 1 and FM_Score in (4, 5) then 'Cant Lose Them'
            when R_Score = 1 and FM_Score = 1 then 'Lost'
            else 'Undefined'
            end as "Cust_Segment"
from rfm; 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-- Question Three: 

-- 1
------
with diff_date as(  
select cust_id,  Calendar_Dt, Calendar_Dt  - "rank" AS date_diff
from (
        select cust_id , Calendar_Dt , row_number() over(partition by cust_id  order by calendar_dt) "rank"
        from customertransaction) 
)

select cust_id , max(consecutive_days) as max_consecutive_days
from( 
        select cust_id , count(date_diff) as consecutive_days
        from diff_date
        group by cust_id , date_diff 
        )
group by cust_id
order by cust_id ; 
 
------------------------------------------------------------------------------------------------------
-- 2
------
with rank_amt as(
select cust_id ,total_amt , row_number() over(partition by cust_id order by total_amt) as rank
from (
        select cust_id , sum(amt_le) over(partition by cust_id order by calendar_dt) as total_amt
        from customertransaction
        ) 
)
select round(avg(count_cust_days),2) as avg_days
from( select cust_id , 
         min(case when total_amt >= 250 then rank end ) as count_cust_days
        from  rank_amt 
        group by cust_id
        ) ; 

