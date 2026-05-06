CREATE TABLE Order (
    id BIGINT,
    personId INTEGER,
    orderNumber VARCHAR(50),
    status VARCHAR(20),
    createdAt TIMESTAMP,
    updatedAt TIMESTAMP,
    totalAmount DECIMAL(12,2)
);
