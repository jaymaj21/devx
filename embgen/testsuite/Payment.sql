CREATE TABLE Payment (
    id BIGINT,
    orderId BIGINT,
    amount DECIMAL(12,2),
    currency VARCHAR(3),
    method VARCHAR(50),
    status VARCHAR(20),
    processedAt TIMESTAMP
);
