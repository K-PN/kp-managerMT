CREATE TABLE customers (
    id TEXT PRIMARY KEY NOT NULL,
    search_key TEXT NOT NULL,
    payload BLOB NOT NULL
);
CREATE INDEX customers_search ON customers(search_key);
CREATE TABLE attachments (
    id TEXT PRIMARY KEY NOT NULL,
    payload BLOB NOT NULL
);
CREATE TABLE transactions (
    id TEXT PRIMARY KEY NOT NULL,
    customer_id TEXT NOT NULL REFERENCES customers(id),
    amount INTEGER NOT NULL CHECK(amount > 0),
    effective_date REAL NOT NULL,
    kind TEXT NOT NULL,
    reversal_of TEXT UNIQUE REFERENCES transactions(id),
    import_key TEXT UNIQUE,
    payload BLOB NOT NULL,
    CHECK((kind = 'reversal' AND reversal_of IS NOT NULL) OR (kind <> 'reversal' AND reversal_of IS NULL))
);
CREATE INDEX transactions_customer_date ON transactions(customer_id, effective_date);
CREATE INDEX transactions_date_kind ON transactions(effective_date, kind);
CREATE TABLE audit (
    id TEXT PRIMARY KEY NOT NULL,
    entity_id TEXT NOT NULL,
    timestamp REAL NOT NULL,
    payload BLOB NOT NULL
);
CREATE INDEX audit_entity_time ON audit(entity_id, timestamp);
CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit BEGIN SELECT RAISE(ABORT, 'audit immutable'); END;
CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit BEGIN SELECT RAISE(ABORT, 'audit immutable'); END;
CREATE TABLE drafts (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL);
