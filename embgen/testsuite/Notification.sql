CREATE TABLE Notification (
    id BIGINT,
    userId INTEGER,
    channel VARCHAR(50),
    payload VARCHAR(4000),
    status VARCHAR(20),
    createdAt TIMESTAMP
);
