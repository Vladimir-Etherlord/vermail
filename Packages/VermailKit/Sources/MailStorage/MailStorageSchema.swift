@preconcurrency import GRDB

extension MailDatabase {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { database in
            try database.create(table: "messages") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("account_id", .text).notNull()
                table.column("remote_uid", .text).notNull()
                table.column("folder", .text).notNull()
                table.column("subject", .text)
                table.column("from_address", .text)
                table.column("to_addresses", .text).notNull().defaults(to: "")
                table.column("snippet", .text)
                table.column("received_at", .datetime)
                table.column("is_read", .boolean).notNull().defaults(to: false)
                table.column("has_attachments", .boolean).notNull().defaults(to: false)
                table.column("raw_file_path", .text).notNull()
                table.column("size_bytes", .integer).notNull()
                table.column("created_at", .datetime).notNull()
                table.column("updated_at", .datetime).notNull()
            }

            try database.create(
                index: "idx_messages_account_uid",
                on: "messages",
                columns: ["account_id", "remote_uid"],
                options: .unique
            )

            try database.create(
                index: "idx_messages_folder_account_received",
                on: "messages",
                columns: ["folder", "account_id", "received_at"]
            )

            try database.create(table: "pop3_uidl_state") { table in
                table.column("account_id", .text).notNull()
                table.column("remote_uid", .text).notNull()
                table.column("message_id", .integer).references("messages", onDelete: .setNull)
                table.column("last_seen_at", .datetime).notNull()
                table.primaryKey(["account_id", "remote_uid"])
            }

            try database.create(virtualTable: "message_search", using: FTS5()) { table in
                table.column("subject")
                table.column("snippet")
                table.column("from_address")
                table.column("to_addresses")
                table.tokenizer = .unicode61()
                table.synchronize(withTable: "messages")
            }
        }

        return migrator
    }
}
