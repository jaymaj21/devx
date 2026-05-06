--embgen_embedded_generator xml_driven_macro 99999999-9999-9999-9999-999999999999
-- @types.xml {/types/type} {
--     table_name = xpathnode.attributes['name']
--     target_tables ||= []
--     unless target_tables.any? && !target_tables.include?(table_name)
--         if defined?(base_dir)
--             out_path = File.join(base_dir, "#{table_name}.sql")
--         else
--             out_path = "#{table_name}.sql"
--         end
--         emit_file out_path do
--             emit "CREATE TABLE #{table_name} (\n"
--             fields = xpathnode.elements.to_a('fields/field')
--             fields.each_with_index do |field_node, idx|
--                 cname = field_node.attributes['name']
--                 ctype = field_node.attributes['dbtype']
--                 emit ",\n" unless idx.zero?
--                 emit "    #{cname} #{ctype}"
--             end
--             emit "\n);\n"
--         end
--         emit "#{@context.comment_line("generated file: #{out_path}")}\n"
--         emit "\n"
--     end
-- }
--embgen_generated_start 99999999-9999-9999-9999-999999999999
-- generated file: Person.sql

-- generated file: Address.sql

-- generated file: Order.sql

-- generated file: OrderItem.sql

-- generated file: Product.sql

-- generated file: Category.sql

-- generated file: InventoryItem.sql

-- generated file: Warehouse.sql

-- generated file: Payment.sql

-- generated file: Invoice.sql

-- generated file: Shipment.sql

-- generated file: UserAccount.sql

-- generated file: UserProfile.sql

-- generated file: Role.sql

-- generated file: Permission.sql

-- generated file: RolePermission.sql

-- generated file: AuditEvent.sql

-- generated file: Notification.sql

-- generated file: ConfigEntry.sql

-- generated file: FeatureFlag.sql

-- generated file: Tenant.sql


--embgen_generated_end 99999999-9999-9999-9999-999999999999
