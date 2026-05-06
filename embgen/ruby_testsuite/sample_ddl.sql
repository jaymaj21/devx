--embgen_embedded_generator xml_driven_macro 22222222-2222-2222-2222-222222222222
    -- @types.xml {/types/type} {
    --     table_name = xpathnode.attributes['name']
    --     emit "CREATE TABLE #{table_name} (\n"
    --     xpathnode.elements.each_with_index('fields/field') do |field, idx|
    --         emit ",\n" unless idx.zero?
    --         emit "    #{field.attributes['name']} #{field.attributes['dbtype']}"
    --     end
    --     emit "\n);\n\n"
    -- }
    --embgen_generated_start 22222222-2222-2222-2222-222222222222
    CREATE TABLE Person (
        id INTEGER,
        firstName VARCHAR(255),
        lastName VARCHAR(255),
        email VARCHAR(255),
        dateOfBirth VARCHAR(20),
        phoneNumber VARCHAR(50),
        status VARCHAR(20)
    );

    CREATE TABLE Address (
        id INTEGER,
        personId INTEGER,
        street VARCHAR(255),
        city VARCHAR(255),
        state VARCHAR(255),
        zipCode VARCHAR(20),
        country VARCHAR(255)
    );

    CREATE TABLE Order (
        id BIGINT,
        personId INTEGER,
        orderNumber VARCHAR(50),
        status VARCHAR(20),
        createdAt TIMESTAMP,
        updatedAt TIMESTAMP,
        totalAmount DECIMAL(12,2)
    );

    CREATE TABLE OrderItem (
        id BIGINT,
        orderId BIGINT,
        productId INTEGER,
        quantity INTEGER,
        unitPrice DECIMAL(12,2),
        lineTotal DECIMAL(12,2)
    );

    CREATE TABLE Product (
        id INTEGER,
        sku VARCHAR(50),
        name VARCHAR(255),
        description VARCHAR(2000),
        price DECIMAL(12,2),
        currency VARCHAR(3),
        active BOOLEAN
    );

    CREATE TABLE Category (
        id INTEGER,
        name VARCHAR(255),
        description VARCHAR(1000),
        parentId INTEGER
    );

    CREATE TABLE InventoryItem (
        id INTEGER,
        productId INTEGER,
        warehouseId INTEGER,
        quantity INTEGER,
        reserved INTEGER
    );

    CREATE TABLE Warehouse (
        id INTEGER,
        code VARCHAR(50),
        name VARCHAR(255),
        location VARCHAR(255),
        capacity INTEGER
    );

    CREATE TABLE Payment (
        id BIGINT,
        orderId BIGINT,
        amount DECIMAL(12,2),
        currency VARCHAR(3),
        method VARCHAR(50),
        status VARCHAR(20),
        processedAt TIMESTAMP
    );

    CREATE TABLE Invoice (
        id BIGINT,
        orderId BIGINT,
        invoiceNumber VARCHAR(50),
        issuedAt TIMESTAMP,
        dueAt TIMESTAMP,
        total DECIMAL(12,2)
    );

    CREATE TABLE Shipment (
        id BIGINT,
        orderId BIGINT,
        trackingId VARCHAR(100),
        carrier VARCHAR(100),
        status VARCHAR(20),
        shippedAt TIMESTAMP,
        deliveredAt TIMESTAMP
    );

    CREATE TABLE UserAccount (
        id INTEGER,
        username VARCHAR(100),
        hashedPassword VARCHAR(255),
        email VARCHAR(255),
        role VARCHAR(50),
        active BOOLEAN
    );

    CREATE TABLE UserProfile (
        id INTEGER,
        userId INTEGER,
        firstName VARCHAR(255),
        lastName VARCHAR(255),
        avatarUrl VARCHAR(500),
        bio VARCHAR(2000)
    );

    CREATE TABLE Role (
        id INTEGER,
        name VARCHAR(100),
        description VARCHAR(1000)
    );

    CREATE TABLE Permission (
        id INTEGER,
        code VARCHAR(100),
        description VARCHAR(1000)
    );

    CREATE TABLE RolePermission (
        roleId INTEGER,
        permissionId INTEGER
    );

    CREATE TABLE AuditEvent (
        id BIGINT,
        userId INTEGER,
        eventType VARCHAR(100),
        eventTime TIMESTAMP,
        details VARCHAR(2000)
    );

    CREATE TABLE Notification (
        id BIGINT,
        userId INTEGER,
        channel VARCHAR(50),
        payload VARCHAR(4000),
        status VARCHAR(20),
        createdAt TIMESTAMP
    );

    CREATE TABLE ConfigEntry (
        id INTEGER,
        key VARCHAR(255),
        value VARCHAR(4000),
        scope VARCHAR(50),
        updatedAt TIMESTAMP
    );

    CREATE TABLE FeatureFlag (
        id INTEGER,
        name VARCHAR(255),
        enabled BOOLEAN,
        rollout INTEGER
    );

    CREATE TABLE Tenant (
        id INTEGER,
        code VARCHAR(50),
        name VARCHAR(255),
        active BOOLEAN
    );


    --embgen_generated_end 22222222-2222-2222-2222-222222222222
