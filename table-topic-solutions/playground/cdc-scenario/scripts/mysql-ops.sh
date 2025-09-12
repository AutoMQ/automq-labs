#!/bin/bash

# MySQL Database Operations Script for CDC Scenario

DB_USER="root"
DB_PASS="debezium"
DB_NAME="sampledb"
DEFAULT_TABLE="users"

# Execute SQL command through Docker Compose
mysql_exec() {
    docker compose exec -T mysql mysql -h localhost -u $DB_USER -p$DB_PASS $DB_NAME -e "$1"
}

# Get a random user ID from the database
get_random_user_id() {
    mysql_exec "SELECT id FROM users ORDER BY RAND() LIMIT 1;" | tail -n 1
}

case "$1" in
    "show-table")
        table_name=${2:-$DEFAULT_TABLE}
        echo "👥 Current data in '$table_name' table:"
        mysql_exec "SELECT * FROM $table_name ORDER BY id DESC LIMIT 20;"
        ;;

    "insert-random")
        timestamp=$(date +%s)
        random_id=$(shuf -i 1000-9999 -n 1)
        first_name="User${random_id}"
        last_name="Test${timestamp}"
        email="user.${random_id}.${timestamp}@example.com"
        
        echo "➕ Inserting random user: $first_name $last_name"
        mysql_exec "INSERT INTO users (first_name, last_name, email) VALUES ('$first_name', '$last_name', '$email');"
        echo "✅ User inserted successfully"
        ;;

    "update-random")
        user_id=${2}
        if [ -z "$user_id" ]; then
            user_id=$(get_random_user_id)
            if [ -z "$user_id" ] || [ "$user_id" = "id" ]; then
                echo "❌ No users found to update"
                exit 1
            fi
        fi
        
        timestamp=$(date +%s)
        new_email="updated.${user_id}.${timestamp}@example.com"
        
        echo "✏️  Updating user ID: $user_id"
        mysql_exec "UPDATE users SET email='$new_email', updated_at=CURRENT_TIMESTAMP WHERE id=$user_id;"
        echo "✅ User updated successfully"
        ;;

    "delete-random")
        user_id=${2}
        if [ -z "$user_id" ]; then
            user_id=$(get_random_user_id)
            if [ -z "$user_id" ] || [ "$user_id" = "id" ]; then
                echo "❌ No users found to delete"
                exit 1
            fi
        fi
        
        echo "🗑️  Deleting user ID: $user_id"
        mysql_exec "DELETE FROM users WHERE id=$user_id;"
        echo "✅ User deleted successfully"
        ;;

    "batch-insert")
        count=${2:-10}
        echo "➕ Batch inserting $count random users..."
        for i in $(seq 1 $count); do
            timestamp=$(date +%s)
            random_id=$(shuf -i 10000-99999 -n 1)
            first_name="Batch${random_id}"
            last_name="User${i}"
            email="batch.${random_id}.${i}@example.com"
            mysql_exec "INSERT INTO users (first_name, last_name, email) VALUES ('$first_name', '$last_name', '$email');"
        done
        echo "✅ Batch insert completed for $count users."
        ;;

    "add-column")
        col_name=$2
        col_type=$3
        if [ -z "$col_name" ] || [ -z "$col_type" ]; then
            echo "❌ Usage: $0 add-column <name> <type>"
            exit 1
        fi
        echo "➕ Adding column '$col_name' with type '$col_type' to users table..."
        mysql_exec "ALTER TABLE users ADD COLUMN $col_name $col_type;"
        echo "✅ Column added successfully"
        ;;

    "drop-column")
        col_name=$2
        if [ -z "$col_name" ]; then
            echo "❌ Usage: $0 drop-column <name>"
            exit 1
        fi
        echo "🗑️  Dropping column '$col_name' from users table..."
        mysql_exec "ALTER TABLE users DROP COLUMN $col_name;"
        echo "✅ Column dropped successfully"
        ;;

    "truncate-table")
        table_name=${2:-$DEFAULT_TABLE}
        echo "🧹 Truncating '$table_name' table..."
        mysql_exec "TRUNCATE TABLE $table_name;"
        echo "✅ Table truncated successfully"
        ;;

    *)
        echo "MySQL Database Operations Script for CDC Scenario"
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Available commands:"
        echo "  show-table [table_name]    - Show current table data (default: users)"
        echo "  insert-random              - Insert a random user record"
        echo "  update-random [id]         - Update a random user (or by ID)"
        echo "  delete-random [id]         - Delete a random user (or by ID)"
        echo "  batch-insert [count]       - Batch insert random users (default: 10)"
        echo "  add-column <name> <type>   - Add a new column to the users table"
        echo "  drop-column <name>         - Drop a column from the users table"
        echo "  truncate-table [table_name]- Clear all data from a table (default: users)"
        ;;
esac