CREATE TABLE Shipment (
    id BIGINT,
    orderId BIGINT,
    trackingId VARCHAR(100),
    carrier VARCHAR(100),
    status VARCHAR(20),
    shippedAt TIMESTAMP,
    deliveredAt TIMESTAMP
);
