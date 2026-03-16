-- 015_create_intel_labels.sql
-- Entity labels and evidence-backed attributions.
-- Used to label known addresses (exchanges, foundations, pools, etc.)
-- for enriching hop traces and analytics.
--
-- Rollback: DROP TABLE IF EXISTS intel_labels.entities, intel_labels.entity_addresses,
--           intel_labels.entity_stake_keys, intel_labels.evidence CASCADE;

BEGIN;

-- Known entities (exchanges, foundations, projects, etc.)
CREATE TABLE IF NOT EXISTS intel_labels.entities (
    entity_id       SERIAL PRIMARY KEY,
    name            TEXT NOT NULL UNIQUE,
    category        TEXT NOT NULL,  -- exchange, foundation, project, pool_operator, whale, unknown
    description     TEXT,
    website         TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Map addresses to entities
CREATE TABLE IF NOT EXISTS intel_labels.entity_addresses (
    id              SERIAL PRIMARY KEY,
    entity_id       INTEGER NOT NULL REFERENCES intel_labels.entities(entity_id),
    address         TEXT NOT NULL,
    label           TEXT,           -- e.g. "hot wallet", "deposit address", "treasury"
    confidence      TEXT NOT NULL DEFAULT 'UNKNOWN',  -- FACT, STRONG_INFERENCE, WEAK_INFERENCE, UNKNOWN
    first_seen_epoch INTEGER,
    last_seen_epoch  INTEGER,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entity_id, address)
);

CREATE INDEX IF NOT EXISTS idx_entity_addresses_addr
    ON intel_labels.entity_addresses (address);

CREATE INDEX IF NOT EXISTS idx_entity_addresses_entity
    ON intel_labels.entity_addresses (entity_id);

-- Map stake keys to entities
CREATE TABLE IF NOT EXISTS intel_labels.entity_stake_keys (
    id              SERIAL PRIMARY KEY,
    entity_id       INTEGER NOT NULL REFERENCES intel_labels.entities(entity_id),
    stake_address   TEXT NOT NULL,
    label           TEXT,
    confidence      TEXT NOT NULL DEFAULT 'UNKNOWN',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (entity_id, stake_address)
);

CREATE INDEX IF NOT EXISTS idx_entity_stake_keys_stake
    ON intel_labels.entity_stake_keys (stake_address);

-- Evidence: why we believe an address/entity mapping
CREATE TABLE IF NOT EXISTS intel_labels.evidence (
    id              SERIAL PRIMARY KEY,
    entity_address_id INTEGER REFERENCES intel_labels.entity_addresses(id),
    entity_stake_key_id INTEGER REFERENCES intel_labels.entity_stake_keys(id),
    evidence_type   TEXT NOT NULL,  -- co_input, known_label, api_response, manual, chain_pattern
    evidence_class  TEXT NOT NULL DEFAULT 'UNKNOWN',  -- FACT, STRONG_INFERENCE, WEAK_INFERENCE
    source          TEXT NOT NULL,  -- e.g. "blockfrost label api", "co-input with known addr X", "manual"
    tx_hash         TEXT,           -- supporting transaction if applicable
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT evidence_has_target CHECK (
        entity_address_id IS NOT NULL OR entity_stake_key_id IS NOT NULL
    )
);

-- Seed well-known entities
INSERT INTO intel_labels.entities (name, category, description) VALUES
    ('IOG', 'foundation', 'Input Output Global — Cardano development company'),
    ('EMURGO', 'foundation', 'EMURGO — Cardano commercial adoption entity'),
    ('Cardano Foundation', 'foundation', 'Cardano Foundation — ecosystem stewardship'),
    ('Binance', 'exchange', 'Binance cryptocurrency exchange'),
    ('Coinbase', 'exchange', 'Coinbase cryptocurrency exchange'),
    ('Kraken', 'exchange', 'Kraken cryptocurrency exchange'),
    ('Bitfinex', 'exchange', 'Bitfinex cryptocurrency exchange'),
    ('KuCoin', 'exchange', 'KuCoin cryptocurrency exchange'),
    ('Huobi', 'exchange', 'Huobi cryptocurrency exchange'),
    ('Gate.io', 'exchange', 'Gate.io cryptocurrency exchange')
ON CONFLICT (name) DO NOTHING;

COMMIT;
