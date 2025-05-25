-- Utworzenie bazy danych z parametrami
CREATE DATABASE aparatka
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LOCALE_PROVIDER = 'libc'
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

COMMENT ON DATABASE aparatka
    IS 'Baza danych analizatorów wykonujących badania w Organizacji.';


-- Rozszerzenie pgcrypto dla szyfrowania haseł w tabeli users
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Tabele słownikowe (zoptymalizowane)
CREATE TABLE analyzer_types (
    type_id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);

COMMENT ON TABLE analyzer_types
IS 'W tabeli zebrane są dostępne typy aparatów: biochemiczny/immunochemiczny/POCT/hematologiczny/...';

CREATE TABLE manufacturers (
    manufacturer_id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);
COMMENT ON TABLE manufacturers
IS 'W tabeli zebrane są dostępni dostawcy/producenci analizatorów';

CREATE TABLE models (
    model_id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    manufacturer_id SMALLINT NOT NULL REFERENCES manufacturers(manufacturer_id),
    type_id SMALLINT NOT NULL REFERENCES analyzer_types(type_id)
);

COMMENT ON TABLE models
IS 'W tabeli zebrane są modele aparatów, np.: Integra 400+, Sysmex XN-550/...';

CREATE TABLE locations (
    location_id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);
COMMENT ON TABLE locations
IS 'W tabeli zebrane informacje o lokalizacjach w jakich mogą stać analizatory: laboratorium/punkt_pobrań/Klient/...';


CREATE TABLE statuses (
    status_id SMALLSERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE
);
COMMENT ON TABLE statuses
	IS 'W tabeli zebrane są dostępne statusy aparatów, np.: nowy/w użyciu/wycofany/testy/inny/...';

-- 2. Tabele główne
CREATE TABLE analyzers (
    analyzer_id SERIAL PRIMARY KEY,
    serial_number TEXT NOT NULL UNIQUE,
    name TEXT NOT NULL,
    model_id SMALLINT NOT NULL REFERENCES models(model_id),
    production_year INT,
    ownership_type TEXT DEFAULT 'lease' CHECK (ownership_type IN ('owned', 'lease')),
    purchase_date DATE,
    retirement_date DATE DEFAULT NULL,
    status_id SMALLINT REFERENCES statuses(status_id),
    other VARCHAR(150)
);

CREATE TABLE fees (
    fee_id SERIAL PRIMARY KEY,
    analyzer_id INT REFERENCES analyzers(analyzer_id),
    amount DECIMAL(10,2),
    monthly_lease_fee DECIMAL(10,2) DEFAULT NULL,
    date DATE,
    description TEXT
);
COMMENT ON TABLE fees
IS 'Tabela opłat za aparaty';

CREATE TABLE laboratories (
    laboratory_id SERIAL PRIMARY KEY,
    external_id TEXT UNIQUE,
    name TEXT NOT NULL,
    address TEXT,
    symbol VARCHAR(7) NOT NULL UNIQUE,
    performs_tests BOOLEAN DEFAULT TRUE
);

COMMENT ON TABLE laboratories
IS 'W tabeli zebrane są informacje o aktualnych laboratoriach.';


CREATE TABLE analyzer_locations (
    analyzer_location_id SERIAL PRIMARY KEY,
    analyzer_id INT NOT NULL REFERENCES analyzers(analyzer_id),
    location_id SMALLINT NOT NULL REFERENCES locations(location_id),
    laboratory_id INT REFERENCES laboratories(laboratory_id),
    analyzer_name TEXT,
    marcel_symbol VARCHAR(7) UNIQUE,
    purpose TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    start_date DATE NOT NULL,
    end_date DATE CHECK (end_date IS NULL OR end_date > start_date)
);
COMMENT ON TABLE analyzer_locations
IS 'W tabeli są zawarte informacje o konkretnym aparacie w danym laboratorium. Odpowiada danym w systemie laboratoryjnym';

CREATE TABLE test_counts (
    test_id SERIAL PRIMARY KEY,
    analyzer_location_id INT NOT NULL REFERENCES analyzer_locations(analyzer_location_id),
    count INT NOT NULL,
    date DATE NOT NULL
);

COMMENT ON TABLE test_counts
IS 'Liczba badań wykonanych przez konkretny analizator w określonym czasie';

-- 3. Tabele dodatkowe
CREATE TABLE audit_log (
    audit_id SERIAL PRIMARY KEY,
    table_name TEXT NOT NULL,
    operation TEXT NOT NULL,
    record_id TEXT,
    old_value TEXT,
    new_value TEXT,
    change_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    changed_by TEXT DEFAULT current_user
);

COMMENT ON TABLE audit_log
IS 'Tabela audytowa pokazująca historię zmian';


CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    password TEXT NOT NULL, -- Zaszyfrowane za pomocą pgcrypto
    role TEXT NOT NULL CHECK (role IN ('admin', 'operations', 'rapo')),
    email VARCHAR(255) UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE
);
COMMENT ON TABLE users
    IS 'Tabela użytkowników';
	
CREATE TABLE login_attempts (
    attempt_id SERIAL PRIMARY KEY,
    user_id INT REFERENCES users(user_id),
    attempt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    success BOOLEAN NOT NULL
);
COMMENT ON TABLE login_attempts
    IS 'Historia prób logowania użytkowników.';

--4. Wersjonowanie bazy
CREATE TABLE schema_version (
    version_id SERIAL PRIMARY KEY,
    version_number VARCHAR(10) NOT NULL,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);
INSERT INTO schema_version (version_number, description) 
VALUES ('1.0', 'Pierwsza wersja bazy aparatka');	
	
-- 5. Funkcja audytowa
CREATE OR REPLACE FUNCTION log_audit_changes()
RETURNS TRIGGER AS $$
DECLARE
    primary_key_value TEXT;
BEGIN
    primary_key_value := (row_to_json(NEW)->>(SELECT column_name FROM information_schema.columns 
                                              WHERE table_name = TG_TABLE_NAME 
                                              AND column_name LIKE '%_id' LIMIT 1))::TEXT;
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, new_value)
        VALUES (TG_TABLE_NAME, 'INSERT', primary_key_value, row_to_json(NEW)::TEXT);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        primary_key_value := (row_to_json(OLD)->>(SELECT column_name FROM information_schema.columns 
                                                  WHERE table_name = TG_TABLE_NAME 
                                                  AND column_name LIKE '%_id' LIMIT 1))::TEXT;
        INSERT INTO audit_log (table_name, operation, record_id, old_value, new_value)
        VALUES (TG_TABLE_NAME, 'UPDATE', primary_key_value, row_to_json(OLD)::TEXT, row_to_json(NEW)::TEXT);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        primary_key_value := (row_to_json(OLD)->>(SELECT column_name FROM information_schema.columns 
                                                  WHERE table_name = TG_TABLE_NAME 
                                                  AND column_name LIKE '%_id' LIMIT 1))::TEXT;
        INSERT INTO audit_log (table_name, operation, record_id, old_value)
        VALUES (TG_TABLE_NAME, 'DELETE', primary_key_value, row_to_json(OLD)::TEXT);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Triggery audytowe
CREATE TRIGGER audit_analyzer_types
    AFTER INSERT OR UPDATE OR DELETE ON analyzer_types
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_manufacturers
    AFTER INSERT OR UPDATE OR DELETE ON manufacturers
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_models
    AFTER INSERT OR UPDATE OR DELETE ON models
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_locations
    AFTER INSERT OR UPDATE OR DELETE ON locations
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_statuses
    AFTER INSERT OR UPDATE OR DELETE ON statuses
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_analyzers
    AFTER INSERT OR UPDATE OR DELETE ON analyzers
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_fees
    AFTER INSERT OR UPDATE OR DELETE ON fees
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_laboratories
    AFTER INSERT OR UPDATE OR DELETE ON laboratories
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_test_counts
    AFTER INSERT OR UPDATE OR DELETE ON test_counts
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_analyzer_locations
    AFTER INSERT OR UPDATE OR DELETE ON analyzer_locations
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

CREATE TRIGGER audit_users
    AFTER INSERT OR UPDATE OR DELETE ON users
    FOR EACH ROW EXECUTE FUNCTION log_audit_changes();

-- 7. Tworzenie ról i uprawnienia
CREATE ROLE admin_role WITH LOGIN PASSWORD '*****';
CREATE ROLE operations_role WITH LOGIN PASSWORD '*****';
CREATE ROLE rapo_role WITH LOGIN PASSWORD '*****';

-- Uprawnienia dla admin_role
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_role;
ALTER ROLE admin_role WITH CREATEROLE;


-- Uprawnienia dla operations_role
GRANT SELECT, INSERT, UPDATE ON analyzer_types TO operations_role;
GRANT SELECT, INSERT, UPDATE ON manufacturers TO operations_role;
GRANT SELECT, INSERT, UPDATE ON models TO operations_role;
GRANT SELECT, INSERT, UPDATE ON locations TO operations_role;
GRANT SELECT, INSERT, UPDATE ON statuses TO operations_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON analyzers TO operations_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON fees TO operations_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON laboratories TO operations_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON test_counts TO operations_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON analyzer_locations TO operations_role;
GRANT SELECT, INSERT, UPDATE ON audit_log TO operations_role;

GRANT USAGE, SELECT, UPDATE ON SEQUENCE analyzer_types_type_id_seq TO operations_role;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE manufacturers_manufacturer_id_seq TO operations_role;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE models_model_id_seq TO operations_role;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE locations_location_id_seq TO operations_role;
GRANT USAGE, SELECT, UPDATE ON SEQUENCE statuses_status_id_seq TO operations_role;

GRANT SELECT, INSERT ON login_attempts TO operations_role; -- Operations może logować próby
GRANT USAGE, SELECT, UPDATE ON SEQUENCE login_attempts_attempt_id_seq TO operations_role;


-- Uprawnienia dla rapo_role
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rapo_role;


--8. Indeksy

-- Indeks na marcel_symbol w analyzer_locations 
CREATE UNIQUE INDEX idx_analyzer_locations_marcel_symbol ON analyzer_locations(marcel_symbol);

-- Indeks na symbol w laboratories )
CREATE UNIQUE INDEX idx_laboratories_symbol ON laboratories(symbol);



