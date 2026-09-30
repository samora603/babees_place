import re
import psycopg2


# ============================================================
# PostgreSQL connection
# ============================================================

PG_CONFIG = {
    "host": "127.0.0.1",
    "port": 5432,
    "dbname": "babees_migration",
    "user": "babees_migrator",
    "password": "BabeesMigration2026",
}


OUTPUT_FILE = "babees_mariadb_schema.sql"


# ============================================================
# Identifier helpers
# ============================================================

def quote_identifier(identifier):
    escaped = identifier.replace("`", "``")
    return f"`{escaped}`"


# ============================================================
# PostgreSQL -> MariaDB type mapping
# ============================================================

def map_type(column):
    data_type = column["data_type"]
    udt_name = column["udt_name"]

    if data_type == "uuid":
        return "CHAR(36)"

    if data_type == "text":
        return "TEXT"

    if data_type == "jsonb":
        return "JSON"

    if data_type == "boolean":
        return "TINYINT(1)"

    if data_type == "smallint":
        return "SMALLINT"

    if data_type == "integer":
        return "INT"

    if data_type == "bigint":
        return "BIGINT"

    if data_type == "numeric":
        precision = column["numeric_precision"]
        scale = column["numeric_scale"]

        if precision is not None and scale is not None:
            return f"DECIMAL({precision},{scale})"

        # PostgreSQL numeric without precision/scale.
        # Based on actual Babees Place data, DECIMAL(12,2)
        # is sufficient for these monetary values.
        return "DECIMAL(12,2)"

    if data_type == "timestamp with time zone":
        return "DATETIME"

    if data_type == "timestamp without time zone":
        return "DATETIME"

    if data_type == "date":
        return "DATE"

    if data_type == "time without time zone":
        return "TIME"

    if data_type == "character varying":
        max_length = column["character_maximum_length"]

        if max_length:
            return f"VARCHAR({max_length})"

        return "TEXT"

    if data_type == "character":
        max_length = column["character_maximum_length"]

        if max_length:
            return f"CHAR({max_length})"

        return "CHAR(1)"

    if data_type == "real":
        return "FLOAT"

    if data_type == "double precision":
        return "DOUBLE"

    # Safe fallback.
    print(
        f"WARNING: unmapped PostgreSQL type "
        f"{data_type!r} / {udt_name!r}; using TEXT"
    )

    return "TEXT"


# ============================================================
# PostgreSQL default -> MariaDB default mapping
# ============================================================

def map_default(default_value):
    if default_value is None:
        return None

    value = default_value.strip()

    # Remove simple PostgreSQL type casts.
    while "::" in value:
        before, after = value.rsplit("::", 1)

        if after.lower() in {
            "smallint",
            "integer",
            "int",
            "bigint",
            "numeric",
            "decimal",
            "real",
            "double precision",
            "boolean",
            "bool",
            "text",
            "varchar",
            "character varying",
            "character",
            "json",
            "jsonb",
            "uuid",
            "timestamp",
            "timestamp without time zone",
            "timestamp with time zone",
        }:
            value = before.strip()
        else:
            break

    # UUID generation defaults are omitted because existing
    # UUID values will be imported explicitly.
    if "gen_random_uuid()" in value.lower():
        return None

    if "uuid_generate_v4()" in value.lower():
        return None

    # PostgreSQL sequence defaults are omitted.
    if "nextval(" in value.lower():
        return None

    # Current timestamp.
    if value.lower() in {
        "now()",
        "current_timestamp",
        "current_timestamp()",
    }:
        return "CURRENT_TIMESTAMP"

    # Boolean defaults.
    if value.lower() in {
        "true",
        "'true'",
    }:
        return "1"

    if value.lower() in {
        "false",
        "'false'",
    }:
        return "0"

    # JSON defaults.
    if value in {
        "'{}'::jsonb",
        "'{}'::json",
        "'{}'",
    }:
        return "'{}'"

    if value in {
        "'[]'::jsonb",
        "'[]'::json",
        "'[]'",
    }:
        return "'[]'"

    return value


# ============================================================
# Load columns
# ============================================================

def load_columns(cur):
    cur.execute(
        """
        SELECT
            table_name,
            column_name,
            data_type,
            udt_name,
            is_nullable,
            column_default,
            numeric_precision,
            numeric_scale,
            character_maximum_length,
            ordinal_position
        FROM information_schema.columns
        WHERE table_schema = 'public'
        ORDER BY table_name, ordinal_position
        """
    )

    columns = {}

    for row in cur.fetchall():
        (
            table_name,
            column_name,
            data_type,
            udt_name,
            is_nullable,
            column_default,
            numeric_precision,
            numeric_scale,
            character_maximum_length,
            ordinal_position,
        ) = row

        columns.setdefault(
            table_name,
            [],
        ).append(
            {
                "table_name": table_name,
                "column_name": column_name,
                "data_type": data_type,
                "udt_name": udt_name,
                "is_nullable": is_nullable,
                "column_default": column_default,
                "numeric_precision": numeric_precision,
                "numeric_scale": numeric_scale,
                "character_maximum_length": character_maximum_length,
                "ordinal_position": ordinal_position,
            }
        )

    return columns


# ============================================================
# Load primary keys
# ============================================================

def load_primary_keys(cur):
    cur.execute(
        """
        SELECT
            tc.table_name,
            kcu.column_name,
            kcu.ordinal_position
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
         AND tc.table_name = kcu.table_name
        WHERE tc.table_schema = 'public'
          AND tc.constraint_type = 'PRIMARY KEY'
        ORDER BY
            tc.table_name,
            kcu.ordinal_position
        """
    )

    primary_keys = {}

    for table_name, column_name, ordinal_position in cur.fetchall():
        primary_keys.setdefault(
            table_name,
            [],
        ).append(column_name)

    return primary_keys


# ============================================================
# Load unique constraints
# ============================================================

def load_unique_constraints(cur):
    cur.execute(
        """
        SELECT
            tc.table_name,
            tc.constraint_name,
            kcu.column_name,
            kcu.ordinal_position
        FROM information_schema.table_constraints tc
        JOIN information_schema.key_column_usage kcu
          ON tc.constraint_name = kcu.constraint_name
         AND tc.table_schema = kcu.table_schema
         AND tc.table_name = kcu.table_name
        WHERE tc.table_schema = 'public'
          AND tc.constraint_type = 'UNIQUE'
        ORDER BY
            tc.table_name,
            tc.constraint_name,
            kcu.ordinal_position
        """
    )

    unique_constraints = {}

    for (
        table_name,
        constraint_name,
        column_name,
        ordinal_position,
    ) in cur.fetchall():

        unique_constraints.setdefault(
            table_name,
            {}
        ).setdefault(
            constraint_name,
            []
        ).append(column_name)

    return unique_constraints


# ============================================================
# Load public -> public foreign keys
# ============================================================

def load_foreign_keys(cur):
    cur.execute(
        """
        SELECT
            child_ns.nspname AS child_schema,
            child_tbl.relname AS child_table,
            child_col.attname AS child_column,
            parent_ns.nspname AS parent_schema,
            parent_tbl.relname AS parent_table,
            parent_col.attname AS parent_column,
            con.conname AS constraint_name,
            CASE con.confdeltype
                WHEN 'a' THEN 'NO ACTION'
                WHEN 'r' THEN 'RESTRICT'
                WHEN 'c' THEN 'CASCADE'
                WHEN 'n' THEN 'SET NULL'
                WHEN 'd' THEN 'SET DEFAULT'
                ELSE 'NO ACTION'
            END AS delete_rule,
            CASE con.confupdtype
                WHEN 'a' THEN 'NO ACTION'
                WHEN 'r' THEN 'RESTRICT'
                WHEN 'c' THEN 'CASCADE'
                WHEN 'n' THEN 'SET NULL'
                WHEN 'd' THEN 'SET DEFAULT'
                ELSE 'NO ACTION'
            END AS update_rule,
            child_col.attnum AS child_attnum
        FROM pg_constraint con

        JOIN pg_class child_tbl
          ON child_tbl.oid = con.conrelid

        JOIN pg_namespace child_ns
          ON child_ns.oid = child_tbl.relnamespace

        JOIN pg_class parent_tbl
          ON parent_tbl.oid = con.confrelid

        JOIN pg_namespace parent_ns
          ON parent_ns.oid = parent_tbl.relnamespace

        JOIN LATERAL unnest(con.conkey)
            WITH ORDINALITY AS child_keys(attnum, ord)
          ON TRUE

        JOIN LATERAL unnest(con.confkey)
            WITH ORDINALITY AS parent_keys(attnum, ord)
          ON parent_keys.ord = child_keys.ord

        JOIN pg_attribute child_col
          ON child_col.attrelid = child_tbl.oid
         AND child_col.attnum = child_keys.attnum

        JOIN pg_attribute parent_col
          ON parent_col.attrelid = parent_tbl.oid
         AND parent_col.attnum = parent_keys.attnum

        WHERE con.contype = 'f'
          AND child_ns.nspname = 'public'
          AND parent_ns.nspname = 'public'

        ORDER BY
            child_ns.nspname,
            child_tbl.relname,
            con.conname,
            child_keys.ord
        """
    )

    foreign_keys = {}

    for row in cur.fetchall():
        (
            child_schema,
            child_table,
            child_column,
            parent_schema,
            parent_table,
            parent_column,
            constraint_name,
            delete_rule,
            update_rule,
            child_attnum,
        ) = row

        foreign_keys.setdefault(
            child_table,
            []
        ).append(
            {
                "constraint_name": constraint_name,
                "child_column": child_column,
                "parent_table": parent_table,
                "parent_column": parent_column,
                "delete_rule": delete_rule,
                "update_rule": update_rule,
            }
        )

    return foreign_keys


# ============================================================
# Diagnostic: count all foreign keys by parent schema
# ============================================================

def load_all_foreign_key_counts(cur):
    cur.execute(
        """
        SELECT
            parent_ns.nspname,
            COUNT(*)
        FROM pg_constraint con

        JOIN pg_class parent_tbl
          ON parent_tbl.oid = con.confrelid

        JOIN pg_namespace parent_ns
          ON parent_ns.oid = parent_tbl.relnamespace

        WHERE con.contype = 'f'

        GROUP BY parent_ns.nspname
        ORDER BY parent_ns.nspname
        """
    )

    return {
        schema: count
        for schema, count in cur.fetchall()
    }


# ============================================================
# Load PostgreSQL indexes
# ============================================================

def load_indexes(cur):
    cur.execute(
        """
        SELECT
            schemaname,
            tablename,
            indexname,
            indexdef
        FROM pg_indexes
        WHERE schemaname = 'public'
        ORDER BY
            tablename,
            indexname
        """
    )

    indexes = []

    for (
        schemaname,
        tablename,
        indexname,
        indexdef,
    ) in cur.fetchall():

        indexes.append(
            {
                "schema": schemaname,
                "table": tablename,
                "name": indexname,
                "definition": indexdef,
            }
        )

    return indexes


# ============================================================
# Parse simple PostgreSQL index columns
# ============================================================

def parse_index_columns(indexdef):
    match = re.search(
        r"\((.*)\)",
        indexdef,
        re.DOTALL,
    )

    if not match:
        return []

    inside = match.group(1).strip()

    parts = []

    current = []
    depth = 0

    for char in inside:
        if char == "(":
            depth += 1

        elif char == ")":
            depth -= 1

        if char == "," and depth == 0:
            parts.append(
                "".join(current).strip()
            )
            current = []
        else:
            current.append(char)

    if current:
        parts.append(
            "".join(current).strip()
        )

    result = []

    for part in parts:
        # Skip expressions.
        if "(" in part:
            return []

        # Remove PostgreSQL ordering/null modifiers.
        part = re.sub(
            r"\s+(ASC|DESC)\b",
            "",
            part,
            flags=re.IGNORECASE,
        )

        part = re.sub(
            r"\s+NULLS\s+(FIRST|LAST)\b",
            "",
            part,
            flags=re.IGNORECASE,
        )

        part = part.strip()

        # Remove quotes around identifiers.
        if part.startswith('"') and part.endswith('"'):
            part = part[1:-1].replace(
                '""',
                '"',
            )

        result.append(part)

    return result


# ============================================================
# Index classification
# ============================================================

def is_partial(indexdef):
    return " WHERE " in indexdef.upper()


def is_primary_index(name):
    return name.lower().endswith("_pkey")


def is_unique_index(indexdef):
    return "CREATE UNIQUE INDEX" in indexdef.upper()


def is_expression_index(indexdef):
    upper = indexdef.upper()

    # PostgreSQL expression indexes commonly contain
    # function calls inside the index column definition.
    match = re.search(
        r"\((.*)\)",
        indexdef,
        re.DOTALL,
    )

    if not match:
        return False

    inside = match.group(1)

    return "(" in inside


# ============================================================
# MariaDB index-column formatting
# ============================================================

def format_index_columns(
    index_columns,
    columns_by_table,
    table,
):
    """
    MariaDB/InnoDB cannot index unrestricted TEXT columns.

    Use a 191-character prefix for TEXT columns.

    191 * 4 bytes = 764 bytes under utf8mb4.
    """

    table_columns = {
        column["column_name"]: column
        for column in columns_by_table.get(
            table,
            [],
        )
    }

    formatted = []

    for column in index_columns:

        column_info = table_columns.get(
            column
        )

        if column_info is None:
            formatted.append(
                quote_identifier(column)
            )
            continue

        data_type = (
            column_info["data_type"]
            or ""
        ).lower()

        if data_type in {
            "text",
            "character varying",
            "varchar",
            "character",
        }:
            formatted.append(
                f"{quote_identifier(column)}(191)"
            )
        else:
            formatted.append(
                quote_identifier(column)
            )

    return ", ".join(formatted)


# ============================================================
# Main
# ============================================================

def main():

    connection = psycopg2.connect(
        **PG_CONFIG
    )

    cur = connection.cursor()

    columns = load_columns(cur)
    primary_keys = load_primary_keys(cur)
    unique_constraints = load_unique_constraints(cur)
    foreign_keys = load_foreign_keys(cur)
    indexes = load_indexes(cur)
    fk_counts = load_all_foreign_key_counts(cur)

    cur.close()
    connection.close()

    print("Foreign-key diagnostic:")

    for schema in sorted(fk_counts):
        print(
            f"  {schema}: {fk_counts[schema]}"
        )

    print()

    with open(
        OUTPUT_FILE,
        "w",
        encoding="utf-8",
    ) as out:

        out.write(
            "-- =====================================================\n"
        )
        out.write(
            "-- Babees Place PostgreSQL -> MariaDB schema\n"
        )
        out.write(
            "-- Generated automatically. Review before execution.\n"
        )
        out.write(
            "-- =====================================================\n\n"
        )

        out.write(
            "SET FOREIGN_KEY_CHECKS = 0;\n"
        )

        out.write(
            "SET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';\n\n"
        )

        # ====================================================
        # TABLES
        # ====================================================

        for table in sorted(columns):

            out.write(
                f"CREATE TABLE IF NOT EXISTS "
                f"{quote_identifier(table)} (\n"
            )

            definitions = []

            for column in columns[table]:

                name = quote_identifier(
                    column["column_name"]
                )

                sql_type = map_type(
                    column
                )

                nullable = (
                    "NULL"
                    if column["is_nullable"] == "YES"
                    else "NOT NULL"
                )

                default = map_default(
                    column["column_default"]
                )

                definition = (
                    f"  {name} "
                    f"{sql_type} "
                    f"{nullable}"
                )

                if default is not None:
                    definition += (
                        f" DEFAULT {default}"
                    )

                definitions.append(
                    definition
                )

            # Primary key.
            pk = primary_keys.get(
                table,
                []
            )

            if pk:

                pk_sql = ", ".join(
                    quote_identifier(column)
                    for column in pk
                )

                definitions.append(
                    f"  PRIMARY KEY ({pk_sql})"
                )

            # Unique constraints.
            for (
                constraint_name,
                unique_columns,
            ) in unique_constraints.get(
                table,
                {},
            ).items():

                cols = format_index_columns(
                    unique_columns,
                    columns,
                    table,
                )

                definitions.append(
                    f"  UNIQUE KEY "
                    f"{quote_identifier(constraint_name)} "
                    f"({cols})"
                )

            out.write(
                ",\n".join(
                    definitions
                )
            )

            out.write(
                "\n) "
                "ENGINE=InnoDB "
                "DEFAULT CHARSET=utf8mb4 "
                "COLLATE=utf8mb4_unicode_ci;\n\n"
            )

        # ====================================================
        # ORDINARY INDEXES
        # ====================================================

        out.write(
            "-- =====================================================\n"
        )
        out.write(
            "-- Ordinary indexes\n"
        )
        out.write(
            "-- =====================================================\n\n"
        )

        for index in indexes:

            table = index["table"]
            name = index["name"]
            definition = index["definition"]

            if is_primary_index(name):
                continue

            if is_partial(definition):

                out.write(
                    f"-- SKIPPED PARTIAL INDEX: "
                    f"{table}.{name}\n"
                )

                out.write(
                    f"-- PostgreSQL: {definition}\n\n"
                )

                continue

            if is_expression_index(
                definition
            ):

                out.write(
                    f"-- SKIPPED EXPRESSION INDEX: "
                    f"{table}.{name}\n"
                )

                out.write(
                    f"-- PostgreSQL: {definition}\n\n"
                )

                continue

            if is_unique_index(
                definition
            ):

                out.write(
                    f"-- SKIPPED UNIQUE INDEX "
                    f"(handled by constraint): "
                    f"{table}.{name}\n"
                )

                continue

            index_columns = parse_index_columns(
                definition
            )

            if not index_columns:

                out.write(
                    f"-- SKIPPED UNPARSED INDEX: "
                    f"{table}.{name}\n"
                )

                out.write(
                    f"-- PostgreSQL: {definition}\n\n"
                )

                continue

            cols = format_index_columns(
                index_columns,
                columns,
                table,
            )

            out.write(
                f"CREATE INDEX "
                f"{quote_identifier(name)} "
                f"ON {quote_identifier(table)} "
                f"({cols});\n"
            )

        # ====================================================
        # FOREIGN KEYS
        # ====================================================

        out.write(
            "\n-- =====================================================\n"
        )
        out.write(
            "-- Foreign keys: public -> public only\n"
        )
        out.write(
            "-- =====================================================\n\n"
        )

        for table in sorted(
            foreign_keys
        ):

            for fk in foreign_keys[
                table
            ]:

                constraint_name = quote_identifier(
                    fk["constraint_name"]
                )

                child_column = quote_identifier(
                    fk["child_column"]
                )

                parent_table = quote_identifier(
                    fk["parent_table"]
                )

                parent_column = quote_identifier(
                    fk["parent_column"]
                )

                delete_rule = fk[
                    "delete_rule"
                ]

                update_rule = fk[
                    "update_rule"
                ]

                out.write(
                    f"ALTER TABLE "
                    f"{quote_identifier(table)}\n"
                )

                out.write(
                    f"  ADD CONSTRAINT "
                    f"{constraint_name}\n"
                )

                out.write(
                    f"  FOREIGN KEY "
                    f"({child_column})\n"
                )

                out.write(
                    f"  REFERENCES "
                    f"{parent_table} "
                    f"({parent_column})\n"
                )

                if delete_rule != "NO ACTION":
                    out.write(
                        f"  ON DELETE "
                        f"{delete_rule}\n"
                    )

                if update_rule != "NO ACTION":
                    out.write(
                        f"  ON UPDATE "
                        f"{update_rule}\n"
                    )

                out.write(";\n\n")

        out.write(
            "-- Supabase auth.users relationships "
            "are intentionally omitted.\n"
        )

        out.write(
            "SET FOREIGN_KEY_CHECKS = 1;\n"
        )

    print(
        f"Generated: {OUTPUT_FILE}"
    )

    print(
        f"Tables: {len(columns)}"
    )

    print(
        "Foreign keys: "
        f"{sum(len(v) for v in foreign_keys.values())}"
    )

    print(
        f"Indexes inspected: {len(indexes)}"
    )


if __name__ == "__main__":
    main()
