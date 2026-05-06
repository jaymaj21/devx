CREATE TABLE UserAccount (
    id INTEGER,
    username VARCHAR(100),
    hashedPassword VARCHAR(255),
    email VARCHAR(255),
    role VARCHAR(50),
    active BOOLEAN
);
