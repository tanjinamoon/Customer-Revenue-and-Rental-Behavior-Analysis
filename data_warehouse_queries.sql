USE sakila;

DROP TABLE IF EXISTS rental_behavior;

CREATE TABLE rental_behavior AS
SELECT 
    r.rental_id,
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS full_name, 
    f.film_id,
    f.title AS film_title,
    cat.name AS category_name,
    i.store_id,
    r.rental_date,
    r.return_date,
    DATEDIFF(r.return_date, r.rental_date) AS rental_duration,
    
    -- Determine if the rental was returned late
    CASE 
        WHEN r.return_date > DATE_ADD(r.rental_date, INTERVAL f.rental_duration DAY) 
        THEN 1 
        ELSE 0 
    END AS late_return,

    -- Extract time-based attributes for advanced queries
    DAYNAME(r.rental_date) AS rental_weekday,
    MONTHNAME(r.rental_date) AS rental_month,
    YEAR(r.rental_date) AS rental_year,
    
    -- Payment Information
    p.amount AS payment_amount,
    
    -- Staff Member Who Processed the Rental
    r.staff_id
FROM rental r
JOIN customer c ON r.customer_id = c.customer_id
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film f ON i.film_id = f.film_id
JOIN film_category fc ON f.film_id = fc.film_id
JOIN category cat ON fc.category_id = cat.category_id
LEFT JOIN payment p ON r.rental_id = p.rental_id;

SELECT * FROM rental_behavior
LIMIT 25;

-- 01. Customer Segmentation - Identifying High-Value & Low-Value Customers
SELECT 
    customer_id, 
    full_name, 
    COUNT(rental_id) AS total_rentals, 
    SUM(payment_amount) AS total_spent, 
    ROUND(SUM(payment_amount) / COUNT(rental_id), 2) AS avg_spent_per_rental,
    CASE 
        WHEN COUNT(rental_id) > (SELECT AVG(total_rentals) FROM 
            (SELECT COUNT(rental_id) AS total_rentals FROM rental_behavior GROUP BY customer_id) AS subquery)
        AND (SUM(payment_amount) / COUNT(rental_id)) < (SELECT AVG(avg_spent) FROM 
            (SELECT SUM(payment_amount) / COUNT(rental_id) AS avg_spent FROM rental_behavior GROUP BY customer_id) AS subquery)
        THEN 'High Rentals, Low Spend'
        
        WHEN COUNT(rental_id) < (SELECT AVG(total_rentals) FROM 
            (SELECT COUNT(rental_id) AS total_rentals FROM rental_behavior GROUP BY customer_id) AS subquery)
        AND (SUM(payment_amount) / COUNT(rental_id)) > (SELECT AVG(avg_spent) FROM 
            (SELECT SUM(payment_amount) / COUNT(rental_id) AS avg_spent FROM rental_behavior GROUP BY customer_id) AS subquery)
        THEN 'Low Rentals, High Spend'
        
        ELSE 'Balanced'
    END AS customer_segment
FROM rental_behavior
GROUP BY customer_id, full_name
ORDER BY total_rentals DESC;



-- 02. Store Efficiency Analysis - Revenue Per Rental and Late Return Rate
SELECT 
    store_id, 
    COUNT(rental_id) AS total_rentals, 
    SUM(payment_amount) AS total_revenue, 
    (SUM(payment_amount) / COUNT(rental_id)) AS avg_revenue_per_rental, 
    SUM(late_return) AS total_late_returns, 
    (SUM(late_return) / COUNT(rental_id)) * 100 AS late_return_percentage
FROM rental_behavior
GROUP BY store_id
ORDER BY avg_revenue_per_rental DESC, late_return_percentage ASC;



-- 03. Seasonal Trends - Identifying Peak Rental Months
SELECT 
    rental_month, 
    rental_year, 
    COUNT(rental_id) AS total_rentals, 
    SUM(payment_amount) AS total_revenue, 
    (SUM(payment_amount) / COUNT(rental_id)) AS avg_spent_per_rental
FROM rental_behavior
GROUP BY rental_year, rental_month
ORDER BY total_rentals DESC;



-- 04. Late Return Patterns - Who Returns Movies Late the Most?
SELECT 
    customer_id, 
    full_name, 
    COUNT(rental_id) AS total_rentals, 
    SUM(late_return) AS late_returns, 
    (SUM(late_return) / COUNT(rental_id)) * 100 AS late_return_percentage, 
    GROUP_CONCAT(DISTINCT film_title ORDER BY film_title ASC SEPARATOR ', ') AS most_rented_movies
FROM rental_behavior
GROUP BY customer_id, full_name
HAVING late_return_percentage > 50
ORDER BY late_return_percentage DESC;



-- 05. Customer Loyalty - Identifying Long-Term vs. One-Time Renters
SELECT 
    customer_id, 
    full_name, 
    COUNT(DISTINCT rental_year) AS active_years, 
    COUNT(rental_id) AS total_rentals, 
    SUM(payment_amount) AS total_spent,
    CASE 
        WHEN COUNT(DISTINCT rental_year) >= 3 THEN 'Loyal Customer'
        WHEN COUNT(DISTINCT rental_year) = 2 THEN 'Occasional Customer'
        ELSE 'One-Time Customer'
    END AS customer_loyalty_segment
FROM rental_behavior
GROUP BY customer_id, full_name
ORDER BY active_years DESC, total_rentals DESC;



-- 06. Staff Performance - Identifying the Best and Worst Performing Staff
SELECT 
    staff_id, 
    COUNT(rental_id) AS rentals_processed, 
    SUM(payment_amount) AS total_revenue_generated, 
    (SUM(payment_amount) / COUNT(rental_id)) AS avg_revenue_per_rental
FROM rental_behavior
GROUP BY staff_id
ORDER BY total_revenue_generated DESC, avg_revenue_per_rental DESC;



-- 07. Movie Category Trends - Which Genres Perform Best Over Time?
SELECT 
    category_name, 
    rental_year, 
    COUNT(film_id) AS total_rentals, 
    SUM(payment_amount) AS total_revenue, 
    ROUND(AVG(payment_amount), 2) AS avg_spent_per_rental
FROM rental_behavior
GROUP BY category_name, rental_year
ORDER BY rental_year ASC, total_rentals DESC;


-- 08. Store vs. Customer Comparison – Identifying the Most Profitable Customer for Each Store
SELECT store_id, customer_id, full_name, total_spent
FROM (
    SELECT 
        store_id, 
        customer_id, 
        full_name, 
        SUM(payment_amount) AS total_spent,
        RANK() OVER (PARTITION BY store_id ORDER BY SUM(payment_amount) DESC) AS rank_order
    FROM rental_behavior
    GROUP BY store_id, customer_id, full_name
) ranked
WHERE rank_order = 1;



-- 09. Identifying the Most Profitable Movie Based on Repeat Customers
SELECT film_title, COUNT(DISTINCT customer_id) AS unique_customers, COUNT(rental_id) AS total_rentals, SUM(payment_amount) AS total_revenue
FROM rental_behavior
WHERE film_id IN (
    SELECT film_id FROM rental_behavior GROUP BY film_id, customer_id HAVING COUNT(rental_id) > 2
)
GROUP BY film_title
ORDER BY total_rentals DESC, total_revenue DESC;


-- 10. Store Performance by Rental Duration & Late Returns
SELECT 
    store_id, 
    COUNT(rental_id) AS total_rentals,
    ROUND(AVG(rental_duration), 2) AS avg_rental_days,
    SUM(late_return) AS total_late_returns,
    ROUND((SUM(late_return) / COUNT(rental_id)) * 100, 2) AS late_return_percentage
FROM rental_behavior
GROUP BY store_id
ORDER BY avg_rental_days DESC, late_return_percentage DESC;



-- 11. Revenue Analysis – Comparing Rentals with & Without Late Fees
SELECT 
    rental_year,
    COUNT(rental_id) AS total_rentals,
    SUM(CASE WHEN late_return = 1 THEN payment_amount ELSE 0 END) AS revenue_from_late_returns,
    SUM(CASE WHEN late_return = 0 THEN payment_amount ELSE 0 END) AS revenue_from_on_time_returns,
    ROUND(
        (SUM(CASE WHEN late_return = 1 THEN payment_amount ELSE 0 END) / SUM(payment_amount)) * 100, 2
    ) AS late_fee_revenue_percentage
FROM rental_behavior
GROUP BY rental_year
ORDER BY rental_year ASC;


-- 12. Identifying "Dead" Customers Who Haven’t Rented in the Last Year
SELECT customer_id, full_name, MAX(rental_date) AS last_rental_date
FROM rental_behavior
WHERE customer_id NOT IN (
    SELECT DISTINCT customer_id 
    FROM rental_behavior 
    WHERE rental_date >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
)
GROUP BY customer_id, full_name
ORDER BY last_rental_date DESC;




