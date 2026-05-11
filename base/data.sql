-- Initialize specific database for Fleet Service
CREATE DATABASE IF NOT EXISTS fleet_tst 
CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

DROP USER IF EXISTS 'fleet-svc'@'%';
DROP USER IF EXISTS 'fleet-svc'@'localhost';
DROP USER IF EXISTS 'fleet-svc'@'%'; 

-- Create user and password (Replace 'FleetSVC_PassChangeMe!Secure123' with a vault secret ref)
CREATE USER 'fleet-svc'@'%' IDENTIFIED BY 'FleetSVC_PassChangeMe!Secure123';
GRANT ALL PRIVILEGES ON fleet_tst.* TO 'fleet-svc'@'%';
GRANT ALL PRIVILEGES ON fleet_tst.* TO 'fleet-svc'@'localhost';

FLUSH PRIVILEGES;
