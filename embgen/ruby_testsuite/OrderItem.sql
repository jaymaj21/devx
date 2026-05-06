CREATE TABLE OrderItem (
    id BIGINT,
    orderId BIGINT,
    productId INTEGER,
    quantity INTEGER,
    unitPrice DECIMAL(12,2),
    lineTotal DECIMAL(12,2)
);
