//! SupportDesk demo app
//!
//! This binary intentionally contains very little hand-written domain code.
//! The XML schema drives generation of:
//! - Rust domain structs
//! - SQLite table creation and DAO functions
//! - JSON serde helpers
//! - TinyProto binary serializer/deserializer helpers

use rusqlite::Connection;
use xml_schema_macro::generate_app_schema;

generate_app_schema!("schema/customer_support.xml");

use generated_domain::{dao, Agent, Customer, Ticket, TicketMessage};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let conn = Connection::open_in_memory()?;
    dao::create_tables(&conn)?;

    let customer = Customer {
        id: 1,
        email: "ada@example.com".to_string(),
        display_name: "Ada Lovelace".to_string(),
        vip: true,
    };

    let agent = Agent {
        id: 10,
        handle: "grace".to_string(),
        team: "Compiler Support".to_string(),
    };

    let ticket = Ticket {
        id: 100,
        customer_id: customer.id,
        agent_id: agent.id,
        subject: "Procedural macro generated too much useful code".to_string(),
        status: "open".to_string(),
        priority: 1,
    };

    let message = TicketMessage {
        id: 1000,
        ticket_id: ticket.id,
        sender: "customer".to_string(),
        body: "Can one XML file really generate structs, SQL DAOs, JSON, and binary codecs?".to_string(),
        created_at_epoch: 1_725_000_000,
    };

    dao::insert_customer(&conn, &customer)?;
    dao::insert_agent(&conn, &agent)?;
    dao::insert_ticket(&conn, &ticket)?;
    dao::insert_ticket_message(&conn, &message)?;

    let loaded_customer = dao::get_customer_by_id(&conn, 1)?.expect("customer exists");
    println!("Loaded from SQLite: {loaded_customer:#?}");

    let all_tickets = dao::list_tickets(&conn)?;
    println!("Tickets in SQLite: {all_tickets:#?}");

    let json = ticket.to_json_pretty()?;
    println!("Ticket as JSON:\n{json}");
    let ticket_from_json = Ticket::from_json(&json)?;
    assert_eq!(ticket, ticket_from_json);

    let wire = message.to_tinyproto_bytes();
    println!("TicketMessage as TinyProto bytes: {} bytes", wire.len());
    let message_from_wire = TicketMessage::from_tinyproto_bytes(&wire)?;
    assert_eq!(message, message_from_wire);

    println!("Schema path embedded by macro: {}", generated_domain::XML_SCHEMA_PATH);
    println!("Demo complete: all generated layers round-tripped successfully.");

    Ok(())
}
