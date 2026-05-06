
--embgen_embedded_generator xml_driven_macro 99999999-9999-9999-9999-999999999999
-- @"types.xml" {/types/type[@name='Person']/fields/field} { 
--     emit "declare $javatype $name; // $dbtype\n";
--     emit "initialize $javatype $name; // $dbtype\n";
--     
--     
--     }
-- 
-- @"types.xml" {/types/type[@name='Person']/fields/field} { 
--     emit "use $javatype $name; // $dbtype\n";}
-- 
-- @"types.xml" {/types/type[@name='Person']/fields/field} { 
--     emit "finalize $javatype $name; // $dbtype\n";}
-- 
-- @"types.xml" {/types/type[@name='Person']} { emit "\n\n";}
-- 
-- 
-- @"types.xml" {/types/type[@name='Person']/fields/field} { 
--     emit "alter table Person add column [snake_case $name] as $dbtype; \n";
--     
--     }
-- 
--embgen_generated_start 99999999-9999-9999-9999-999999999999
declare int id; // INTEGER
initialize int id; // INTEGER
declare String firstName; // VARCHAR(255)
initialize String firstName; // VARCHAR(255)
declare String lastName; // VARCHAR(255)
initialize String lastName; // VARCHAR(255)
declare String email; // VARCHAR(255)
initialize String email; // VARCHAR(255)
declare String dateOfBirth; // VARCHAR(20)
initialize String dateOfBirth; // VARCHAR(20)
declare String phoneNumber; // VARCHAR(50)
initialize String phoneNumber; // VARCHAR(50)
declare String status; // VARCHAR(20)
initialize String status; // VARCHAR(20)
use int id; // INTEGER
use String firstName; // VARCHAR(255)
use String lastName; // VARCHAR(255)
use String email; // VARCHAR(255)
use String dateOfBirth; // VARCHAR(20)
use String phoneNumber; // VARCHAR(50)
use String status; // VARCHAR(20)
finalize int id; // INTEGER
finalize String firstName; // VARCHAR(255)
finalize String lastName; // VARCHAR(255)
finalize String email; // VARCHAR(255)
finalize String dateOfBirth; // VARCHAR(20)
finalize String phoneNumber; // VARCHAR(50)
finalize String status; // VARCHAR(20)


alter table Person add column id as INTEGER; 
alter table Person add column first_name as VARCHAR(255); 
alter table Person add column last_name as VARCHAR(255); 
alter table Person add column email as VARCHAR(255); 
alter table Person add column date_of_birth as VARCHAR(20); 
alter table Person add column phone_number as VARCHAR(50); 
alter table Person add column status as VARCHAR(20); 

--embgen_generated_end 99999999-9999-9999-9999-999999999999
