CREATE TABLE Invoice (
    id BIGINT,
    orderId BIGINT,
    invoiceNumber VARCHAR(50),
    issuedAt TIMESTAMP,
    dueAt TIMESTAMP,
    total DECIMAL(12,2)
);
