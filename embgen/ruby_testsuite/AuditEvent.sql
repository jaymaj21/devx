CREATE TABLE AuditEvent (
    id BIGINT,
    userId INTEGER,
    eventType VARCHAR(100),
    eventTime TIMESTAMP,
    details VARCHAR(2000)
);
