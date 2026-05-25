-- ================================================================
--  ShopVerse: E-Commerce Database Management System
--  Course   : UCS310 — Database Management Systems
--  Institute: Thapar Institute of Engineering & Technology
--             (Deemed to be University), Patiala, Punjab
--  Students : Animesh Sudhanshu (1024170375)
--             Ashish Bhagat     (1024170372)
--  Group    : 2Q34  |  Submitted To: Gayatri Saxena
--  Session  : Jan-May 2026
-- ================================================================
--  KEY FIXES APPLIED TO ORIGINAL CODE
--  1. phone / seller_phone: INT → BIGINT  (10-digit numbers overflow INT)
--  2. INT(n) display-widths removed        (deprecated in MySQL 8)
--  3. orderitem: added PRIMARY KEY(order_id,product_id)
--  4. orderitem FKs: SET NULL → CASCADE    (PK cols cannot be NULL)
--  5. product_name VARCHAR(50) → 300       (names were truncating)
--  6. seller total_sales seeded to 0;      (triggers/manual UPDATEs set values)
--  7. Product stock adjusted for seed orders
--  8. Orders 5 & 6 set to 'not delivery'  (needed for cursor demo)
--  9. Added: Views, Triggers, Stored Procedures, Functions, Cursors,
--            Complex Queries, Transaction Management
-- 10. FIX — UPDATE customer SET age: added WHERE customer_id > 0
--            (without a KEY-column WHERE clause, MySQL's SQL_SAFE_UPDATES mode
--             blocks the UPDATE with Error 1175)
-- 11. FIX — Transaction Demo 2: stock - 100 → stock - 8
--            (iPhone 15 stock = 9 at that point; -100 gave -91, violating
--             CHECK (stock >= 0) and aborting the statement before the
--             ROLLBACK TO SAVEPOINT could execute)
-- 12. FIX — Transaction Demo 3: wrapped in stored procedure with EXIT HANDLER
--            (bare START TRANSACTION block caused Workbench Error 1452 to
--             surface as a script-level failure; EXIT HANDLER catches the FK
--             violation internally, auto-ROLLBACKs, and prints a clean result)
-- ================================================================

DROP DATABASE IF EXISTS e_commerce;
CREATE DATABASE e_commerce;
USE e_commerce;


-- ================================================================
-- SECTION 1: DDL — TABLE CREATION
-- ================================================================

-- 1. CUSTOMER TABLE
--    'age' is a derived attribute; computed automatically by CalculateAge trigger
CREATE TABLE customer (
    customer_id INT          PRIMARY KEY AUTO_INCREMENT,
    FirstName   VARCHAR(50)  NOT NULL,
    MiddleName  VARCHAR(50),
    LastName    VARCHAR(50)  NOT NULL,
    Email       VARCHAR(100) NOT NULL UNIQUE,
    Phone       BIGINT       NOT NULL,              -- BIGINT: holds 10-digit Indian numbers
    DateOfBirth DATE         NOT NULL,
    age         INT                                  -- derived; set by trigger
);

-- 2. CATEGORY TABLE
CREATE TABLE category (
    category_id   INT          PRIMARY KEY AUTO_INCREMENT,
    category_name VARCHAR(255) NOT NULL UNIQUE,
    Description   VARCHAR(1000)
);

-- 3. SELLER TABLE
CREATE TABLE seller (
    seller_id    INT          PRIMARY KEY AUTO_INCREMENT,
    seller_name  VARCHAR(255) NOT NULL,
    seller_phone BIGINT       NOT NULL,              -- BIGINT for phone numbers
    total_sales  FLOAT        NOT NULL DEFAULT 0     -- updated automatically by trigger
);

-- 4. ADDRESS TABLE  (One customer → many addresses)
CREATE TABLE address (
    address_id  INT          PRIMARY KEY AUTO_INCREMENT,
    apart_no    INT,
    apart_name  VARCHAR(255),
    streetname  VARCHAR(255),
    city        VARCHAR(255) NOT NULL,
    state       VARCHAR(255) NOT NULL,
    pincode     INT          NOT NULL,
    customer_id INT,
    FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE CASCADE ON UPDATE NO ACTION        -- address deleted when customer deleted
);

-- 5. PRODUCT TABLE
CREATE TABLE product (
    product_id   INT          PRIMARY KEY AUTO_INCREMENT,
    product_name VARCHAR(300) NOT NULL,              -- widened from 50 to avoid truncation
    MRP          FLOAT        NOT NULL,
    stock        INT          NOT NULL DEFAULT 0,
    brand        VARCHAR(255),
    category_id  INT,                                -- nullable: ON DELETE SET NULL
    seller_id    INT,                                -- nullable: ON DELETE SET NULL
    CONSTRAINT chk_product_mrp   CHECK (MRP > 0),
    CONSTRAINT chk_product_stock CHECK (stock >= 0),
    FOREIGN KEY (category_id)
        REFERENCES category(category_id)
        ON DELETE SET NULL ON UPDATE NO ACTION,
    FOREIGN KEY (seller_id)
        REFERENCES seller(seller_id)
        ON DELETE SET NULL ON UPDATE NO ACTION
);

-- 6. CART TABLE
CREATE TABLE cart (
    cart_id     INT   PRIMARY KEY AUTO_INCREMENT,
    grandtotal  FLOAT NOT NULL DEFAULT 0,            -- total price of all items in cart
    itemtotal   INT   NOT NULL DEFAULT 0,            -- total quantity of items
    customer_id INT,
    product_id  INT,
    FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE CASCADE ON UPDATE NO ACTION,
    FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE SET NULL ON UPDATE NO ACTION
);

-- 7. ORDER TABLE  ('order' is a reserved keyword in MySQL; using order_table)
CREATE TABLE order_table (
    order_id      INT      PRIMARY KEY AUTO_INCREMENT,
    order_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    order_amount  FLOAT    NOT NULL,
    order_status  ENUM('delivery','not delivery') NOT NULL DEFAULT 'not delivery',
    shipping_date DATETIME,
    customer_id   INT,
    cart_id       INT,
    CONSTRAINT chk_order_amount CHECK (order_amount > 0),
    FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE SET NULL ON UPDATE NO ACTION,
    FOREIGN KEY (cart_id)
        REFERENCES cart(cart_id)
        ON DELETE SET NULL ON UPDATE NO ACTION
);

-- 8. ORDER ITEM TABLE  (Associative entity — composite primary key resolves M:N)
CREATE TABLE orderitem (
    order_id   INT   NOT NULL,
    product_id INT   NOT NULL,
    MRP        FLOAT NOT NULL,
    quantity   INT   NOT NULL,
    PRIMARY KEY (order_id, product_id),              -- composite PK (was missing)
    CONSTRAINT chk_oi_mrp      CHECK (MRP > 0),
    CONSTRAINT chk_oi_quantity CHECK (quantity > 0),
    FOREIGN KEY (order_id)
        REFERENCES order_table(order_id)
        ON DELETE CASCADE ON UPDATE NO ACTION,       -- CASCADE: PK cols cannot be NULL
    FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE CASCADE ON UPDATE NO ACTION
);

-- 9. PAYMENT TABLE
CREATE TABLE payment (
    payment_id    INT  PRIMARY KEY AUTO_INCREMENT,
    paymentMode   ENUM('online','offline') NOT NULL,
    dateofpayment DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    order_id      INT,
    customer_id   INT,
    FOREIGN KEY (order_id)
        REFERENCES order_table(order_id)
        ON DELETE SET NULL ON UPDATE NO ACTION,
    FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE SET NULL ON UPDATE NO ACTION
);

-- 10. REVIEW TABLE
CREATE TABLE review (
    review_id   INT  PRIMARY KEY AUTO_INCREMENT,
    description VARCHAR(500),
    rating      ENUM('1','2','3','4','5') NOT NULL,  -- enforced by ENUM + ValidateRating trigger
    customer_id INT,
    product_id  INT,
    FOREIGN KEY (customer_id)
        REFERENCES customer(customer_id)
        ON DELETE SET NULL ON UPDATE NO ACTION,
    FOREIGN KEY (product_id)
        REFERENCES product(product_id)
        ON DELETE SET NULL ON UPDATE NO ACTION
);


-- ================================================================
-- SECTION 2: DDL — ALTER TABLE EXAMPLES
-- ================================================================

-- ADD: new column to track seller rating/verification
ALTER TABLE seller
    ADD COLUMN is_verified TINYINT(1) NOT NULL DEFAULT 0;

-- MODIFY: extend review description length
ALTER TABLE review
    MODIFY COLUMN description VARCHAR(1000);

-- ADD + DROP: temporary column demonstration
ALTER TABLE product
    ADD COLUMN discount_percent FLOAT NOT NULL DEFAULT 0;

ALTER TABLE product
    DROP COLUMN discount_percent;

-- Cleanup the demo column from seller
ALTER TABLE seller
    DROP COLUMN is_verified;


-- ================================================================
-- SECTION 3: DML — INSERT SAMPLE DATA
-- NOTE: Triggers are defined AFTER this section so they do not
--       interfere with seed data.  Stock and total_sales are
--       adjusted manually below the INSERT blocks.
-- ================================================================

-- CUSTOMER  (age = 0; corrected by UPDATE below until trigger is active)
INSERT INTO customer (customer_id, FirstName, MiddleName, LastName, Email, Phone, DateOfBirth, age) VALUES
    (1, 'Animesh', NULL, 'Sudhanshu', 'itsanimeshs@gmail.com', 9876543210, '2005-09-08', 0),
    (2, 'Devansh', NULL, 'Rathaur',   'devansh@gmail.com',     9876543211, '2005-05-09', 0),
    (3, 'Ashish',  NULL, 'Bhagat',    'abhagat@gmail.com',     9876543212, '2006-06-02', 0);

-- Correct age for existing rows (trigger handles all future INSERTs/UPDATEs)
-- FIX 1: Added WHERE customer_id > 0 so this runs in SQL_SAFE_UPDATES mode
--         (MySQL Workbench blocks UPDATE without a KEY-column WHERE clause)
UPDATE customer SET age = TIMESTAMPDIFF(YEAR, DateOfBirth, CURDATE())
WHERE customer_id > 0;

-- CATEGORY
INSERT INTO category (category_id, category_name, Description) VALUES
    (1, 'Mobiles & Computers',          'Phones, tablets, PCs, desktops and accessories'),
    (2, 'TV, Appliances & Electronics', 'Smart TVs, OLEDs, mixers, and home electronics'),
    (3, 'Men''s Fashion',               'T-shirts, jeans, shirts, kurtas, ethnic wear'),
    (4, 'Women''s Fashion',             'Shorts, kurtis, one-pieces, T-shirts, jeans');

-- SELLER  (total_sales starts at 0; corrected manually below after orderitem inserts)
INSERT INTO seller (seller_id, seller_name, seller_phone, total_sales) VALUES
    (1, 'Raghuram Mahajan', 9295874636, 0),
    (2, 'Nitish Sharma',    7865423565, 0),
    (3, 'Prakash Singh',    7465456456, 0);

-- ADDRESS
INSERT INTO address (address_id, apart_no, apart_name, streetname, city, state, pincode, customer_id) VALUES
    (1, 108, 'Meow Industries',   'Dev Nagar',           'Patiala', 'Punjab', 147004, 1),
    (2, 214, 'Laxmi Enterprises', 'Rawalpindi Road',     'Patiala', 'Punjab', 147004, 2),
    (3,  52, 'Oberoi Traders',    'Thakur Pratap Nagar', 'Patiala', 'Punjab', 147004, 3);

-- PRODUCT
-- Seller mapping: p1(s1), p2(s3), p3(s2), p4(s2), p5(s1), p6(s3), p7(s2), p8(s1), p9(s3), p10(s2)
INSERT INTO product (product_id, product_name, MRP, stock, brand, category_id, seller_id) VALUES
    (1,  'Pen Drive 128GB',    250,   52, 'HP',         2, 1),
    (2,  'Monitor 24 Inch',    25000, 30, 'Dell',       1, 3),
    (3,  'Wireless Keyboard',  765,   69, 'Lenovo',     2, 2),
    (4,  'iPhone 15',          75000, 10, 'Apple',      1, 2),
    (5,  'Men''s T-Shirt',     350,   22, 'H&M',        3, 1),
    (6,  'Men''s Kurta',       766,   32, 'ZARA',       3, 3),
    (7,  'Women''s Shorts',    360,   52, 'Pantaloons',  4, 2),
    (8,  'Women''s Jeans',     699,   65, 'Zudio',      4, 1),
    (9,  'Wireless Mouse',     299,   65, 'Lenovo',     2, 3),
    (10, 'Desktop PC',         25000, 10, 'Dell',       1, 2);

-- CART  (grandtotal = MRP × itemtotal)
INSERT INTO cart (cart_id, grandtotal, itemtotal, customer_id, product_id) VALUES
    (1, 75000, 1, 1, 4),   -- iPhone 15 × 1
    (2,  1050, 3, 2, 5),   -- Men's T-Shirt × 3
    (3,   598, 2, 3, 9),   -- Mouse × 2
    (4,  2160, 6, 2, 7),   -- Women's Shorts × 6
    (5,   250, 1, 1, 1),   -- Pen Drive × 1
    (6,  3830, 5, 3, 6);   -- Men's Kurta × 5

-- ORDER TABLE
-- Orders 5 & 6 intentionally left as 'not delivery' for cursor ProcessPendingOrders demo
INSERT INTO order_table (order_id, order_date, order_amount, order_status, shipping_date, customer_id, cart_id) VALUES
    (1, '2026-05-06 10:12:20', 75000, 'delivery',     '2026-05-07 09:25:02', 1, 1),
    (2, '2026-05-06 20:23:20',  1050, 'delivery',     '2026-05-09 05:29:02', 2, 2),
    (3, '2026-05-08 18:12:20',   598, 'delivery',     '2026-05-09 09:26:02', 3, 3),
    (4, '2026-05-10 15:45:20',  2160, 'delivery',     '2026-05-11 11:26:02', 2, 4),
    (5, '2026-05-10 15:45:20',   250, 'not delivery', NULL,                  1, 5),
    (6, '2026-05-21 16:23:20',  3830, 'not delivery', NULL,                  3, 6);

-- ORDER ITEM
INSERT INTO orderitem (order_id, product_id, MRP, quantity) VALUES
    (1, 4, 75000, 1),   -- iPhone 15 × 1         = ₹75,000  (seller 2)
    (2, 5,   350, 3),   -- Men's T-Shirt × 3      = ₹1,050   (seller 1)
    (3, 9,   299, 2),   -- Wireless Mouse × 2     = ₹598     (seller 3)
    (4, 7,   360, 6),   -- Women's Shorts × 6     = ₹2,160   (seller 2)
    (5, 1,   250, 1),   -- Pen Drive × 1          = ₹250     (seller 1)
    (6, 6,   766, 5);   -- Men's Kurta × 5        = ₹3,830   (seller 3)

-- Adjust product stock to reflect seed orders
-- (UpdateProductStock trigger handles this automatically for future insertions)
UPDATE product SET stock = stock - 1 WHERE product_id = 4;   -- iPhone 15
UPDATE product SET stock = stock - 3 WHERE product_id = 5;   -- Men's T-Shirt
UPDATE product SET stock = stock - 2 WHERE product_id = 9;   -- Mouse
UPDATE product SET stock = stock - 6 WHERE product_id = 7;   -- Women's Shorts
UPDATE product SET stock = stock - 1 WHERE product_id = 1;   -- Pen Drive
UPDATE product SET stock = stock - 5 WHERE product_id = 6;   -- Men's Kurta

-- Adjust seller total_sales based on seed orderitems
-- Seller 1 (Raghuram): p5×3=1050  + p1×1=250      → ₹1,300
-- Seller 2 (Nitish)  : p4×1=75000 + p7×6=2160      → ₹77,160
-- Seller 3 (Prakash) : p9×2=598   + p6×5=3830      → ₹4,428
UPDATE seller SET total_sales = 1300  WHERE seller_id = 1;
UPDATE seller SET total_sales = 77160 WHERE seller_id = 2;
UPDATE seller SET total_sales = 4428  WHERE seller_id = 3;

-- PAYMENT
INSERT INTO payment (paymentMode, dateofpayment, order_id, customer_id) VALUES
    ('online', '2026-05-06 10:12:56', 1, 1),
    ('online', '2026-05-06 20:23:20', 2, 2),
    ('online', '2026-05-08 18:12:20', 3, 3),
    ('online', '2026-05-10 15:45:20', 4, 2),
    ('online', '2026-05-10 15:45:20', 5, 1),
    ('online', '2026-05-21 16:23:20', 6, 3);

-- REVIEW
INSERT INTO review (review_id, description, rating, customer_id, product_id) VALUES
    (1, 'iPhone 15 is amazing — super fast processor and great camera.',   '5', 1, 4),
    (2, 'Nice T-shirts, good quality fabric and stitching.',               '3', 2, 5),
    (3, 'Best mouse I have used — smooth tracking and responsive clicks.',  '4', 3, 9),
    (4, 'Very comfortable shorts, great fit and durable material.',         '4', 2, 7),
    (5, '128GB pen drive with impressive read/write speed, compact size.',  '5', 1, 1),
    (6, 'Kurta sizing is accurate, quality decent but could improve.',      '2', 3, 6);


-- ================================================================
-- SECTION 4: DML — UPDATE AND DELETE EXAMPLES
-- ================================================================

-- UPDATE: Adjust iPhone 15 price after a sale event
UPDATE product SET MRP = 74000 WHERE product_id = 4;

-- UPDATE: Restock Dell Monitor after new shipment
UPDATE product SET stock = stock + 20 WHERE product_id = 2;

-- UPDATE: Update seller contact number
UPDATE seller SET seller_phone = 9999988888 WHERE seller_id = 1;

-- UPDATE: Change customer email
UPDATE customer SET Email = 'animesh.new@gmail.com' WHERE customer_id = 1;

-- DELETE examples (commented to preserve data for demos below)
-- DELETE FROM review WHERE review_id = 6;
-- DELETE FROM orderitem WHERE order_id = 6 AND product_id = 6;  -- cascades to payment via order_table
-- DELETE FROM customer WHERE customer_id = 3;  -- cascades to address (but NOT NULL on order FKs)


-- ================================================================
-- SECTION 5: VIEWS
-- ================================================================

-- View 1: CustomerOrderSummary — customer info + aggregated order data
CREATE OR REPLACE VIEW CustomerOrderSummary AS
SELECT
    c.customer_id,
    CONCAT(c.FirstName, ' ',
           IFNULL(CONCAT(c.MiddleName, ' '), ''),
           c.LastName)                     AS customer_name,
    c.Email,
    c.age,
    COUNT(o.order_id)                      AS total_orders,
    IFNULL(SUM(o.order_amount), 0)         AS total_spent,
    IFNULL(AVG(o.order_amount), 0)         AS avg_order_value
FROM customer c
LEFT JOIN order_table o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.FirstName, c.MiddleName, c.LastName, c.Email, c.age;

-- View 2: ProductReviewRatings — product info + aggregated ratings
CREATE OR REPLACE VIEW ProductReviewRatings AS
SELECT
    p.product_id,
    p.product_name,
    p.brand,
    p.MRP,
    COUNT(r.review_id)                          AS total_reviews,
    ROUND(AVG(CAST(r.rating AS UNSIGNED)), 2)   AS avg_rating
FROM product p
LEFT JOIN review r ON p.product_id = r.product_id
GROUP BY p.product_id, p.product_name, p.brand, p.MRP;

-- View 3: SellerPerformance — seller info + product count + sales
CREATE OR REPLACE VIEW SellerPerformance AS
SELECT
    s.seller_id,
    s.seller_name,
    s.seller_phone,
    s.total_sales,
    COUNT(DISTINCT p.product_id) AS product_count
FROM seller s
LEFT JOIN product p ON s.seller_id = p.seller_id
GROUP BY s.seller_id, s.seller_name, s.seller_phone, s.total_sales;

-- Quick SELECT to verify views
SELECT * FROM CustomerOrderSummary;
SELECT * FROM ProductReviewRatings;
SELECT * FROM SellerPerformance;


-- ================================================================
-- SECTION 6: TRIGGERS (PL/SQL)
-- ================================================================

DELIMITER $$

-- Trigger 1: CalculateAge_Insert
--   Automatically sets 'age' from DateOfBirth before every INSERT on customer.
CREATE TRIGGER CalculateAge_Insert
BEFORE INSERT ON customer
FOR EACH ROW
BEGIN
    SET NEW.age = TIMESTAMPDIFF(YEAR, NEW.DateOfBirth, CURDATE());
END$$

-- Trigger 2: CalculateAge_Update
--   Keeps 'age' in sync whenever a customer record is updated.
CREATE TRIGGER CalculateAge_Update
BEFORE UPDATE ON customer
FOR EACH ROW
BEGIN
    SET NEW.age = TIMESTAMPDIFF(YEAR, NEW.DateOfBirth, CURDATE());
END$$

-- Trigger 3: CheckStockAvailability
--   BEFORE INSERT on orderitem — raises an error if ordered quantity exceeds stock.
CREATE TRIGGER CheckStockAvailability
BEFORE INSERT ON orderitem
FOR EACH ROW
BEGIN
    DECLARE v_available_stock INT DEFAULT 0;

    SELECT stock INTO v_available_stock
    FROM product
    WHERE product_id = NEW.product_id;

    IF v_available_stock < NEW.quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Order failed: insufficient stock available for this product';
    END IF;
END$$

-- Trigger 4: UpdateProductStock
--   AFTER INSERT on orderitem — decrements stock by the ordered quantity.
CREATE TRIGGER UpdateProductStock
AFTER INSERT ON orderitem
FOR EACH ROW
BEGIN
    UPDATE product
    SET stock = stock - NEW.quantity
    WHERE product_id = NEW.product_id;
END$$

-- Trigger 5: UpdateSellerSales
--   AFTER INSERT on orderitem — adds (MRP × qty) to the relevant seller's total_sales.
CREATE TRIGGER UpdateSellerSales
AFTER INSERT ON orderitem
FOR EACH ROW
BEGIN
    UPDATE seller s
    INNER JOIN product p ON p.product_id = NEW.product_id
    SET s.total_sales = s.total_sales + (NEW.MRP * NEW.quantity)
    WHERE s.seller_id = p.seller_id;
END$$

-- Trigger 6: ValidateRating
--   BEFORE INSERT on review — provides a descriptive error for invalid ratings.
--   (ENUM already blocks bad values; this trigger adds a clear error message.)
CREATE TRIGGER ValidateRating
BEFORE INSERT ON review
FOR EACH ROW
BEGIN
    IF NEW.rating NOT IN ('1','2','3','4','5') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Invalid rating: value must be between 1 and 5';
    END IF;
END$$

DELIMITER ;


-- ================================================================
-- SECTION 7: STORED PROCEDURES (PL/SQL)
-- ================================================================

DELIMITER $$

-- Procedure 1: PlaceOrder
--   Creates a new order from a cart and records payment atomically.
--   Demonstrates: START TRANSACTION, SAVEPOINT, COMMIT, ROLLBACK, EXIT HANDLER.
CREATE PROCEDURE PlaceOrder(
    IN  p_customer_id  INT,
    IN  p_cart_id      INT,
    IN  p_payment_mode VARCHAR(10)
)
BEGIN
    DECLARE v_order_amount  FLOAT DEFAULT 0;
    DECLARE v_new_order_id  INT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;                       -- re-raise original error after rollback
    END;

    START TRANSACTION;

        SAVEPOINT sp_start;

        -- Fetch cart grand total as order amount
        SELECT grandtotal INTO v_order_amount
        FROM cart WHERE cart_id = p_cart_id;

        INSERT INTO order_table (order_date, order_amount, order_status,
                                 shipping_date, customer_id, cart_id)
        VALUES (NOW(), v_order_amount, 'not delivery',
                DATE_ADD(NOW(), INTERVAL 3 DAY), p_customer_id, p_cart_id);

        SET v_new_order_id = LAST_INSERT_ID();

        SAVEPOINT sp_after_order;

        INSERT INTO payment (paymentMode, dateofpayment, order_id, customer_id)
        VALUES (p_payment_mode, NOW(), v_new_order_id, p_customer_id);

    COMMIT;

    SELECT v_new_order_id   AS new_order_id,
           v_order_amount   AS order_amount,
           p_payment_mode   AS payment_mode,
           'Order placed successfully' AS status;
END$$


-- Procedure 2: UpdateOrderStatus
--   Updates order_status and sets shipping_date when marking as delivered.
CREATE PROCEDURE UpdateOrderStatus(
    IN p_order_id INT,
    IN p_status   VARCHAR(20)
)
BEGIN
    IF p_status = 'delivery' THEN
        UPDATE order_table
        SET order_status  = 'delivery',
            shipping_date = NOW()
        WHERE order_id = p_order_id;
    ELSE
        UPDATE order_table
        SET order_status  = 'not delivery',
            shipping_date = NULL
        WHERE order_id = p_order_id;
    END IF;

    SELECT p_order_id AS order_id,
           p_status   AS new_status,
           ROW_COUNT() AS rows_updated;
END$$


-- Procedure 3: AddToCart
--   Inserts a new cart entry after validating stock availability.
CREATE PROCEDURE AddToCart(
    IN p_customer_id INT,
    IN p_product_id  INT,
    IN p_quantity    INT
)
BEGIN
    DECLARE v_mrp             FLOAT DEFAULT 0;
    DECLARE v_available_stock INT   DEFAULT 0;
    DECLARE v_new_cart_id     INT;

    SELECT MRP, stock INTO v_mrp, v_available_stock
    FROM product WHERE product_id = p_product_id;

    IF v_available_stock < p_quantity THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot add to cart: requested quantity exceeds available stock';
    END IF;

    INSERT INTO cart (grandtotal, itemtotal, customer_id, product_id)
    VALUES (v_mrp * p_quantity, p_quantity, p_customer_id, p_product_id);

    SET v_new_cart_id = LAST_INSERT_ID();

    SELECT v_new_cart_id           AS cart_id,
           v_mrp * p_quantity      AS grandtotal,
           p_quantity              AS itemtotal,
           'Item added to cart'    AS message;
END$$


-- Procedure 4: GenerateMonthlySalesReport
--   Returns seller-wise revenue summary for a given year and month.
CREATE PROCEDURE GenerateMonthlySalesReport(
    IN p_year  INT,
    IN p_month INT
)
BEGIN
    SELECT
        s.seller_id,
        s.seller_name,
        COUNT(DISTINCT oi.order_id)             AS total_orders,
        SUM(oi.MRP * oi.quantity)               AS total_revenue,
        ROUND(AVG(oi.MRP * oi.quantity), 2)     AS avg_order_value,
        MAX(oi.MRP * oi.quantity)               AS max_order_value
    FROM orderitem oi
    JOIN order_table o ON oi.order_id   = o.order_id
    JOIN product     p ON oi.product_id = p.product_id
    JOIN seller      s ON p.seller_id   = s.seller_id
    WHERE YEAR(o.order_date)  = p_year
      AND MONTH(o.order_date) = p_month
    GROUP BY s.seller_id, s.seller_name
    ORDER BY total_revenue DESC;
END$$

DELIMITER ;


-- ================================================================
-- SECTION 8: FUNCTIONS (PL/SQL)
-- ================================================================

DELIMITER $$

-- Function 1: CalculateCartTotal
--   Returns the grand total for a given cart_id.
CREATE FUNCTION CalculateCartTotal(p_cart_id INT)
RETURNS FLOAT
READS SQL DATA
BEGIN
    DECLARE v_total FLOAT DEFAULT 0;
    SELECT IFNULL(grandtotal, 0) INTO v_total
    FROM cart WHERE cart_id = p_cart_id;
    RETURN v_total;
END$$


-- Function 2: GetAverageRating
--   Returns the average rating for a product (0 if no reviews exist).
CREATE FUNCTION GetAverageRating(p_product_id INT)
RETURNS FLOAT
READS SQL DATA
BEGIN
    DECLARE v_avg FLOAT DEFAULT 0;
    SELECT IFNULL(AVG(CAST(rating AS UNSIGNED)), 0)
    INTO v_avg
    FROM review WHERE product_id = p_product_id;
    RETURN ROUND(v_avg, 2);
END$$


-- Function 3: GetCustomerOrderCount
--   Returns the total number of orders placed by a given customer.
CREATE FUNCTION GetCustomerOrderCount(p_customer_id INT)
RETURNS INT
READS SQL DATA
BEGIN
    DECLARE v_count INT DEFAULT 0;
    SELECT COUNT(*) INTO v_count
    FROM order_table WHERE customer_id = p_customer_id;
    RETURN v_count;
END$$


-- Function 4: CalculateDiscount
--   Returns the discount amount based on order value tier.
--   Tier: >= ₹50,000 → 10%  |  >= ₹10,000 → 5%  |  < ₹10,000 → 0%
CREATE FUNCTION CalculateDiscount(p_order_amount FLOAT)
RETURNS FLOAT
DETERMINISTIC
NO SQL
BEGIN
    DECLARE v_discount FLOAT DEFAULT 0;
    IF p_order_amount >= 50000 THEN
        SET v_discount = p_order_amount * 0.10;
    ELSEIF p_order_amount >= 10000 THEN
        SET v_discount = p_order_amount * 0.05;
    END IF;
    RETURN v_discount;
END$$

DELIMITER ;


-- ================================================================
-- SECTION 9: CURSORS (PL/SQL)
-- ================================================================

DELIMITER $$

-- Cursor 1: ProcessPendingOrders
--   Iterates over all 'not delivery' orders and marks each as delivered.
CREATE PROCEDURE ProcessPendingOrders()
BEGIN
    DECLARE v_done     INT DEFAULT FALSE;
    DECLARE v_order_id INT;
    DECLARE v_count    INT DEFAULT 0;

    DECLARE cur_pending CURSOR FOR
        SELECT order_id FROM order_table WHERE order_status = 'not delivery';
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    OPEN cur_pending;
    pending_loop: LOOP
        FETCH cur_pending INTO v_order_id;
        IF v_done THEN LEAVE pending_loop; END IF;

        UPDATE order_table
        SET order_status  = 'delivery',
            shipping_date = NOW()
        WHERE order_id = v_order_id;

        SET v_count = v_count + 1;
    END LOOP;
    CLOSE cur_pending;

    SELECT v_count AS orders_processed,
           'All pending orders marked as delivered' AS message;
END$$


-- Cursor 2: GenerateCustomerReport
--   Loops through all customers and produces a purchase statistics report.
CREATE PROCEDURE GenerateCustomerReport()
BEGIN
    DECLARE v_done        INT     DEFAULT FALSE;
    DECLARE v_cust_id     INT;
    DECLARE v_name        VARCHAR(150);
    DECLARE v_orders      INT     DEFAULT 0;
    DECLARE v_total_spent FLOAT   DEFAULT 0;

    DECLARE cur_cust CURSOR FOR
        SELECT customer_id, CONCAT(FirstName, ' ', LastName) FROM customer;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    DROP TEMPORARY TABLE IF EXISTS temp_customer_report;
    CREATE TEMPORARY TABLE temp_customer_report (
        customer_name VARCHAR(150),
        total_orders  INT,
        total_spent   FLOAT
    );

    OPEN cur_cust;
    cust_loop: LOOP
        FETCH cur_cust INTO v_cust_id, v_name;
        IF v_done THEN LEAVE cust_loop; END IF;

        SELECT COUNT(*), IFNULL(SUM(order_amount), 0)
        INTO   v_orders, v_total_spent
        FROM order_table WHERE customer_id = v_cust_id;

        INSERT INTO temp_customer_report VALUES (v_name, v_orders, v_total_spent);
    END LOOP;
    CLOSE cur_cust;

    SELECT * FROM temp_customer_report ORDER BY total_spent DESC;
    DROP TEMPORARY TABLE temp_customer_report;
END$$


-- Cursor 3: UpdateLowStockProducts
--   Finds products at or below a given stock threshold and generates a reorder list.
CREATE PROCEDURE UpdateLowStockProducts(IN p_threshold INT)
BEGIN
    DECLARE v_done         INT     DEFAULT FALSE;
    DECLARE v_product_id   INT;
    DECLARE v_product_name VARCHAR(300);
    DECLARE v_stock        INT;
    DECLARE v_seller_name  VARCHAR(255);

    DECLARE cur_low CURSOR FOR
        SELECT p.product_id, p.product_name, p.stock, s.seller_name
        FROM product p
        JOIN seller s ON p.seller_id = s.seller_id
        WHERE p.stock <= p_threshold
        ORDER BY p.stock ASC;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    DROP TEMPORARY TABLE IF EXISTS temp_reorder_list;
    CREATE TEMPORARY TABLE temp_reorder_list (
        product_id    INT,
        product_name  VARCHAR(300),
        current_stock INT,
        seller_name   VARCHAR(255),
        suggested_reorder_qty INT
    );

    OPEN cur_low;
    low_loop: LOOP
        FETCH cur_low INTO v_product_id, v_product_name, v_stock, v_seller_name;
        IF v_done THEN LEAVE low_loop; END IF;

        INSERT INTO temp_reorder_list
        VALUES (v_product_id, v_product_name, v_stock, v_seller_name,
                GREATEST(50 - v_stock, 10));  -- suggest enough to reach 50, min 10
    END LOOP;
    CLOSE cur_low;

    SELECT * FROM temp_reorder_list;
    DROP TEMPORARY TABLE temp_reorder_list;
END$$

DELIMITER ;


-- ================================================================
-- SECTION 10: COMPLEX SELECT QUERIES
-- ================================================================

-- ─── JOINS ───────────────────────────────────────────────────────

-- Q1: INNER JOIN — Full order pipeline: Customer → Order → OrderItem → Product
SELECT
    CONCAT(c.FirstName, ' ', c.LastName)  AS customer_name,
    o.order_id,
    o.order_date,
    o.order_status,
    p.product_name,
    s.seller_name,
    oi.quantity,
    oi.MRP,
    (oi.MRP * oi.quantity)                AS line_total
FROM customer c
INNER JOIN order_table o  ON c.customer_id  = o.customer_id
INNER JOIN orderitem   oi ON o.order_id     = oi.order_id
INNER JOIN product     p  ON oi.product_id  = p.product_id
INNER JOIN seller      s  ON p.seller_id    = s.seller_id
ORDER BY o.order_date;

-- Q2: LEFT JOIN — All customers including those with no orders
SELECT
    c.customer_id,
    CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
    IFNULL(COUNT(o.order_id), 0)         AS total_orders,
    IFNULL(SUM(o.order_amount), 0)       AS total_spent
FROM customer c
LEFT JOIN order_table o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.FirstName, c.LastName;

-- Q3: Multi-table JOIN — Products with category and seller details
SELECT
    p.product_id,
    p.product_name,
    p.MRP,
    p.stock,
    cat.category_name,
    s.seller_name
FROM product p
JOIN category cat ON p.category_id = cat.category_id
JOIN seller   s   ON p.seller_id   = s.seller_id
ORDER BY cat.category_name, p.MRP DESC;

-- Q4: Products sold by the same seller as 'iPhone 15' (self-conceptual join via subquery)
SELECT p.product_name, p.MRP, p.brand
FROM product p
WHERE p.seller_id = (SELECT seller_id FROM product WHERE product_name = 'iPhone 15')
  AND p.product_name != 'iPhone 15';


-- ─── SUBQUERIES ──────────────────────────────────────────────────

-- Q5: Non-correlated subquery — Products priced above overall average MRP
SELECT product_name, MRP, brand
FROM product
WHERE MRP > (SELECT AVG(MRP) FROM product)
ORDER BY MRP DESC;

-- Q6: Derived table subquery — Customers who spent more than ₹50,000 total
SELECT
    CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
    t.total_spent
FROM customer c
JOIN (
    SELECT customer_id, SUM(order_amount) AS total_spent
    FROM order_table
    GROUP BY customer_id
    HAVING SUM(order_amount) > 50000
) t ON c.customer_id = t.customer_id
ORDER BY t.total_spent DESC;

-- Q7: Correlated subquery — Products priced above their own category average
SELECT
    p.product_name,
    p.MRP,
    cat.category_name
FROM product p
JOIN category cat ON p.category_id = cat.category_id
WHERE p.MRP > (
    SELECT AVG(p2.MRP)
    FROM product p2
    WHERE p2.category_id = p.category_id
);

-- Q8: Nested subquery — Seller with highest total_sales
SELECT seller_name, total_sales
FROM seller
WHERE total_sales = (SELECT MAX(total_sales) FROM seller);


-- ─── AGGREGATE FUNCTIONS ─────────────────────────────────────────

-- Q9: COUNT / SUM / AVG per customer
SELECT
    CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
    COUNT(o.order_id)                    AS total_orders,
    SUM(o.order_amount)                  AS total_spent,
    ROUND(AVG(o.order_amount), 2)        AS avg_order_value,
    MAX(o.order_amount)                  AS highest_order,
    MIN(o.order_amount)                  AS lowest_order
FROM customer c
JOIN order_table o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.FirstName, c.LastName;

-- Q10: Revenue per seller (via orderitem)
SELECT
    s.seller_name,
    COUNT(DISTINCT oi.order_id)      AS orders_fulfilled,
    SUM(oi.MRP * oi.quantity)        AS gross_revenue
FROM seller s
JOIN product   p  ON s.seller_id  = p.seller_id
JOIN orderitem oi ON p.product_id = oi.product_id
GROUP BY s.seller_id, s.seller_name
ORDER BY gross_revenue DESC;

-- Q11: AVG / MAX / MIN MRP per category
SELECT
    cat.category_name,
    COUNT(p.product_id)       AS product_count,
    ROUND(AVG(p.MRP), 2)      AS avg_price,
    MAX(p.MRP)                AS max_price,
    MIN(p.MRP)                AS min_price
FROM category cat
JOIN product p ON cat.category_id = p.category_id
GROUP BY cat.category_id, cat.category_name;


-- ─── GROUP BY / HAVING ───────────────────────────────────────────

-- Q12: Sellers whose total revenue exceeds ₹5,000
SELECT
    s.seller_name,
    SUM(oi.MRP * oi.quantity) AS revenue
FROM seller s
JOIN product   p  ON s.seller_id  = p.seller_id
JOIN orderitem oi ON p.product_id = oi.product_id
GROUP BY s.seller_id, s.seller_name
HAVING SUM(oi.MRP * oi.quantity) > 5000
ORDER BY revenue DESC;

-- Q13: Categories with more than 2 products listed
SELECT
    cat.category_name,
    COUNT(p.product_id) AS product_count
FROM category cat
JOIN product p ON cat.category_id = p.category_id
GROUP BY cat.category_id, cat.category_name
HAVING COUNT(p.product_id) > 2;

-- Q14: Customers who spent more than ₹10,000 in total
SELECT
    CONCAT(c.FirstName, ' ', c.LastName) AS customer_name,
    SUM(o.order_amount)                  AS total_spent
FROM customer c
JOIN order_table o ON c.customer_id = o.customer_id
GROUP BY c.customer_id, c.FirstName, c.LastName
HAVING SUM(o.order_amount) > 10000;

-- Q15: Average rating per product (using CAST on ENUM rating)
SELECT
    p.product_name,
    COUNT(r.review_id)                        AS review_count,
    ROUND(AVG(CAST(r.rating AS UNSIGNED)), 1) AS avg_rating
FROM product p
JOIN review r ON p.product_id = r.product_id
GROUP BY p.product_id, p.product_name
ORDER BY avg_rating DESC;


-- ================================================================
-- SECTION 11: TRANSACTION MANAGEMENT
-- ================================================================

-- Demo 1: SUCCESSFUL TRANSACTION (COMMIT)
--   Atomically places a new order and payment for customer 2.
START TRANSACTION;

    SAVEPOINT sp_before_new_order;

    INSERT INTO order_table (order_date, order_amount, order_status,
                             shipping_date, customer_id, cart_id)
    VALUES (NOW(), 765, 'not delivery',
            DATE_ADD(NOW(), INTERVAL 5 DAY), 2, NULL);

    SAVEPOINT sp_after_new_order;

    INSERT INTO payment (paymentMode, dateofpayment, order_id, customer_id)
    VALUES ('online', NOW(), LAST_INSERT_ID(), 2);

COMMIT;
-- Both INSERT statements are saved permanently.


-- Demo 2: ROLLBACK TO SAVEPOINT
--   Simulates an accidental stock deduction and reverts it.
START TRANSACTION;

    SAVEPOINT sp_before_stock_update;

    -- FIX 2: Changed 100 → 8 so the decrement is excessive but valid under CHECK (stock >= 0).
    --         iPhone 15 stock is 9 here; 9-8=1 is still ≥ 0 and demonstrates the "mistake".
    --         The original -100 would cause stock=-91, violating CHECK (stock >= 0),
    --         crashing the statement before ROLLBACK TO SAVEPOINT could execute.
    UPDATE product SET stock = stock - 8 WHERE product_id = 4;

    -- Realise the mistake — roll back only to savepoint
    ROLLBACK TO SAVEPOINT sp_before_stock_update;

    -- Correct update: deduct 1 unit
    UPDATE product SET stock = stock - 1 WHERE product_id = 4;

COMMIT;
-- Only the correct -1 deduction is applied.


-- Demo 3: FULL ROLLBACK on error
--   FIX 3 (updated): Wrapping the intentional FK violation in a stored
--   procedure with an EXIT HANDLER lets MySQL catch and handle the error
--   internally. The ROLLBACK fires automatically inside the handler, and
--   MySQL Workbench sees a clean execution with no red error row.
--   A bare START TRANSACTION block cannot suppress Error 1452 from Workbench.

DROP PROCEDURE IF EXISTS Demo3_RollbackOnError;

DELIMITER $$
CREATE PROCEDURE Demo3_RollbackOnError()
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Demo 3: FK violation detected — transaction rolled back cleanly. Referential integrity preserved.' AS result;
    END;

    START TRANSACTION;
        -- Intentional FK violation: order_id=999 does not exist in order_table.
        -- The EXIT HANDLER intercepts Error 1452 and issues ROLLBACK automatically.
        INSERT INTO orderitem (order_id, product_id, MRP, quantity)
        VALUES (999, 1, 250, 1);
    COMMIT; -- never reached; handler fires first
END$$
DELIMITER ;

CALL Demo3_RollbackOnError();
DROP PROCEDURE IF EXISTS Demo3_RollbackOnError;
-- No changes are committed; referential integrity is preserved.


-- ================================================================
-- SECTION 12: STORED PROCEDURE & FUNCTION CALLS (DEMOS)
-- ================================================================

-- Add keyboard × 2 to cart for customer 1, then place the order
CALL AddToCart(1, 3, 2);                           -- creates a new cart entry
CALL PlaceOrder(1, LAST_INSERT_ID(), 'online');    -- places order from that cart

-- Mark pending orders as delivered
CALL UpdateOrderStatus(5, 'delivery');
CALL UpdateOrderStatus(6, 'delivery');

-- Process any remaining pending orders via cursor
CALL ProcessPendingOrders();

-- Monthly sales report for May 2026
CALL GenerateMonthlySalesReport(2026, 5);

-- Full customer purchase report
CALL GenerateCustomerReport();

-- Products with stock at or below 15 units
CALL UpdateLowStockProducts(15);

-- Function calls embedded in a SELECT
SELECT
    CalculateCartTotal(1)       AS cart_1_total,
    GetAverageRating(4)         AS iphone_avg_rating,
    GetCustomerOrderCount(1)    AS animesh_total_orders,
    CalculateDiscount(75000)    AS discount_on_75000,
    CalculateDiscount(15000)    AS discount_on_15000,
    CalculateDiscount(5000)     AS discount_on_5000;

-- ================================================================
-- END OF ShopVerse DATABASE SCRIPT
-- ================================================================
