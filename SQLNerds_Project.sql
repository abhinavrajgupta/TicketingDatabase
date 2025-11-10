-- Team Name: SQL Nerds
-- Members: Ivan Lerma, Logan Ferris, Gage Johnson, Nick Sanchez, Abhinav Gupta, Sarthak Dudhani

-- ================================================================================
-- SECTION 1: SESSION SETUP
-- ================================================================================
SET sql_mode = 'STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY';
SET FOREIGN_KEY_CHECKS = 0;

-- ================================================================================
-- SECTION 2: (RE)CREATE SCHEMA
-- ================================================================================

-- Drop database if exists
DROP DATABASE IF EXISTS movie_theater_system;

-- Create database
CREATE DATABASE movie_theater_system;
USE movie_theater_system;

-- Drop tables if they exist (for safety)
DROP TABLE IF EXISTS Ticket;
DROP TABLE IF EXISTS Seat;
DROP TABLE IF EXISTS Showtime;
DROP TABLE IF EXISTS Movie;
DROP TABLE IF EXISTS Theatre;
DROP TABLE IF EXISTS Venue;

-- Create Venue table
CREATE TABLE Venue (
    venue_id INT AUTO_INCREMENT PRIMARY KEY,
    venue_name VARCHAR(100) NOT NULL,
    address VARCHAR(255) NOT NULL,
    UNIQUE KEY unique_venue_address (venue_name, address)
);

-- Create Theatre table (Auditorium)
CREATE TABLE Theatre (
    theatre_id INT AUTO_INCREMENT PRIMARY KEY,
    theatre_name VARCHAR(50) NOT NULL,
    capacity INT NOT NULL CHECK (capacity > 0),
    venue_id INT NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES Venue(venue_id) ON DELETE CASCADE,
    INDEX idx_venue_theatre (venue_id),
    UNIQUE KEY unique_theatre_per_venue (venue_id, theatre_name)
);

-- Create Movie table
CREATE TABLE Movie (
    movie_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    genre VARCHAR(50) NOT NULL,
    duration INT NOT NULL CHECK (duration > 0), -- duration in minutes
    release_year INT NOT NULL CHECK (release_year >= 1900 AND release_year <= 2100),
    rating VARCHAR(10) NOT NULL CHECK (rating IN ('G', 'PG', 'PG-13', 'R', 'NC-17')),
    description TEXT,
    INDEX idx_movie_title (title),
    INDEX idx_movie_genre_year (genre, release_year)
);

-- Create Showtime table
CREATE TABLE Showtime (
    showtime_id INT AUTO_INCREMENT PRIMARY KEY,
    movie_id INT NOT NULL,
    theatre_id INT NOT NULL,
    show_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    FOREIGN KEY (movie_id) REFERENCES Movie(movie_id) ON DELETE CASCADE,
    FOREIGN KEY (theatre_id) REFERENCES Theatre(theatre_id) ON DELETE CASCADE,
    INDEX idx_showtime_date (show_date),
    INDEX idx_showtime_movie_theatre (movie_id, theatre_id),
    -- Constraint to prevent overlapping showtimes in the same theatre
    UNIQUE KEY unique_theatre_showtime (theatre_id, show_date, start_time),
    CHECK (end_time > start_time)
);

-- Create Seat table
CREATE TABLE Seat (
    seat_id INT AUTO_INCREMENT PRIMARY KEY,
    seat_location VARCHAR(10) NOT NULL, -- e.g., 'A1', 'B2', etc.
    seat_type VARCHAR(20) DEFAULT 'STANDARD', -- e.g., 'STANDARD', 'PREMIUM', 'VIP'
    theatre_id INT NOT NULL,
    FOREIGN KEY (theatre_id) REFERENCES Theatre(theatre_id) ON DELETE CASCADE,
    UNIQUE KEY unique_seat_per_theatre (theatre_id, seat_location),
    INDEX idx_theatre_seats (theatre_id)
);

-- Create Ticket table
CREATE TABLE Ticket (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    showtime_id INT NOT NULL,
    seat_id INT NOT NULL,
    booking_status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE' CHECK (booking_status IN ('AVAILABLE', 'RESERVED', 'SOLD')),
    price DECIMAL(6,2) NOT NULL CHECK (price >= 0),
    purchase_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    customer_email VARCHAR(100),
    FOREIGN KEY (showtime_id) REFERENCES Showtime(showtime_id) ON DELETE CASCADE,
    FOREIGN KEY (seat_id) REFERENCES Seat(seat_id) ON DELETE CASCADE,
    -- Prevent double booking of the same seat for the same showtime
    UNIQUE KEY unique_seat_showtime (showtime_id, seat_id),
    INDEX idx_showtime_tickets (showtime_id),
    INDEX idx_booking_status (booking_status)
);

-- Create a view for available seats per showtime
CREATE VIEW Available_Seats AS
SELECT 
    s.showtime_id,
    m.title AS movie_title,
    th.theatre_name,
    v.venue_name,
    s.show_date,
    s.start_time,
    COUNT(CASE WHEN t.booking_status = 'AVAILABLE' OR t.ticket_id IS NULL THEN 1 END) AS available_count,
    th.capacity AS total_capacity
FROM Showtime s
JOIN Movie m ON s.movie_id = m.movie_id
JOIN Theatre th ON s.theatre_id = th.theatre_id
JOIN Venue v ON th.venue_id = v.venue_id
LEFT JOIN Ticket t ON s.showtime_id = t.showtime_id
GROUP BY s.showtime_id;

-- Create trigger to prevent booking tickets for past showtimes
DELIMITER //
CREATE TRIGGER prevent_past_booking
BEFORE INSERT ON Ticket
FOR EACH ROW
BEGIN
    DECLARE show_datetime DATETIME;
    
    SELECT CONCAT(show_date, ' ', start_time) INTO show_datetime
    FROM Showtime
    WHERE showtime_id = NEW.showtime_id;
    
    IF show_datetime < NOW() AND NEW.booking_status IN ('RESERVED', 'SOLD') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot book tickets for past showtimes';
    END IF;
END//
DELIMITER ;

-- Create trigger to update theatre capacity when seats are added/removed
DELIMITER //
CREATE TRIGGER update_capacity_after_seat_change
AFTER INSERT ON Seat
FOR EACH ROW
BEGIN
    UPDATE Theatre 
    SET capacity = (SELECT COUNT(*) FROM Seat WHERE theatre_id = NEW.theatre_id)
    WHERE theatre_id = NEW.theatre_id;
END//
DELIMITER ;

-- Create stored procedure to check seat availability
DELIMITER //
CREATE PROCEDURE CheckSeatAvailability(
    IN p_showtime_id INT,
    IN p_seat_id INT,
    OUT is_available BOOLEAN
)
BEGIN
    DECLARE status VARCHAR(20);
    
    SELECT booking_status INTO status
    FROM Ticket
    WHERE showtime_id = p_showtime_id AND seat_id = p_seat_id
    LIMIT 1;
    
    IF status IS NULL OR status = 'AVAILABLE' THEN
        SET is_available = TRUE;
    ELSE
        SET is_available = FALSE;
    END IF;
END//
DELIMITER ;

-- ================================================================================
-- SECTION 3: SEED DATA (MINIMAL)
-- ================================================================================

-- Insert Venues
INSERT INTO Venue (venue_name, address) VALUES
('AMC Downtown', '123 Main St, New York, NY 10001'),
('Cinemark Plaza', '456 Oak Ave, Los Angeles, CA 90001'),
('Regal Cinema', '789 Pine Rd, Chicago, IL 60601');

-- Insert Theatres
INSERT INTO Theatre (theatre_name, capacity, venue_id) VALUES
('Screen 1', 150, 1),
('Screen 2', 200, 1),
('IMAX', 300, 1),
('Theatre A', 180, 2),
('Theatre B', 160, 2),
('Main Hall', 250, 3);

-- Insert Movies
INSERT INTO Movie (title, genre, duration, release_year, rating, description) VALUES
('The Dark Knight', 'Action', 152, 2008, 'PG-13', 'Batman faces the Joker in this epic superhero thriller.'),
('Inception', 'Sci-Fi', 148, 2010, 'PG-13', 'A thief enters dreams to plant ideas in this mind-bending adventure.'),
('Toy Story 4', 'Animation', 100, 2019, 'G', 'Woody and the gang embark on a new adventure with Forky.'),
('Avengers: Endgame', 'Action', 181, 2019, 'PG-13', 'The Avengers assemble one final time to defeat Thanos.'),
('The Shawshank Redemption', 'Drama', 142, 1994, 'R', 'Two imprisoned men bond over years, finding redemption.'),
('Dune: Part Two', 'Sci-Fi', 166, 2024, 'PG-13', 'Paul Atreides unites with the Fremen to prevent a terrible future.');

-- Insert Showtimes (mix of past and future dates for testing)
INSERT INTO Showtime (movie_id, theatre_id, show_date, start_time, end_time) VALUES
-- Future showtimes (can be booked)
(1, 1, '2025-12-15', '14:00:00', '16:32:00'),
(1, 1, '2025-12-15', '19:00:00', '21:32:00'),
(2, 2, '2025-12-15', '13:30:00', '15:58:00'),
(2, 2, '2025-12-15', '20:00:00', '22:28:00'),
(3, 3, '2025-12-16', '10:00:00', '11:40:00'),
(3, 3, '2025-12-16', '15:00:00', '16:40:00'),
(4, 4, '2025-12-17', '18:00:00', '21:01:00'),
(5, 5, '2025-12-18', '17:30:00', '19:52:00'),
(6, 6, '2025-12-19', '19:30:00', '22:16:00'),
-- Past showtime (for testing past booking prevention)
(1, 1, '2024-10-01', '14:00:00', '16:32:00');

-- Insert Seats (sample seats for each theatre)
-- Theatre 1 seats (Screen 1)
INSERT INTO Seat (seat_location, seat_type, theatre_id) VALUES
('A1', 'PREMIUM', 1), ('A2', 'PREMIUM', 1), ('A3', 'PREMIUM', 1),
('B1', 'STANDARD', 1), ('B2', 'STANDARD', 1), ('B3', 'STANDARD', 1),
('C1', 'STANDARD', 1), ('C2', 'STANDARD', 1), ('C3', 'STANDARD', 1);

-- Theatre 2 seats (Screen 2)
INSERT INTO Seat (seat_location, seat_type, theatre_id) VALUES
('A1', 'VIP', 2), ('A2', 'VIP', 2), ('A3', 'VIP', 2),
('B1', 'PREMIUM', 2), ('B2', 'PREMIUM', 2), ('B3', 'PREMIUM', 2),
('C1', 'STANDARD', 2), ('C2', 'STANDARD', 2), ('C3', 'STANDARD', 2);

-- Theatre 3 seats (IMAX)
INSERT INTO Seat (seat_location, seat_type, theatre_id) VALUES
('A1', 'VIP', 3), ('A2', 'VIP', 3), ('A3', 'VIP', 3),
('B1', 'PREMIUM', 3), ('B2', 'PREMIUM', 3), ('B3', 'PREMIUM', 3),
('C1', 'STANDARD', 3), ('C2', 'STANDARD', 3), ('C3', 'STANDARD', 3);

-- Theatre 4 seats (Theatre A)
INSERT INTO Seat (seat_location, seat_type, theatre_id) VALUES
('A1', 'PREMIUM', 4), ('A2', 'PREMIUM', 4),
('B1', 'STANDARD', 4), ('B2', 'STANDARD', 4),
('C1', 'STANDARD', 4), ('C2', 'STANDARD', 4);

-- Theatre 5 seats (Theatre B)
INSERT INTO Seat (seat_location, seat_type, theatre_id) VALUES
('A1', 'PREMIUM', 5), ('A2', 'PREMIUM', 5),
('B1', 'STANDARD', 5), ('B2', 'STANDARD', 5),
('C1', 'STANDARD', 5), ('C2', 'STANDARD', 5);

-- Theatre 6 seats (Main Hall)
INSERT INTO Seat (seat_location, seat_type, theatre_id) VALUES
('A1', 'VIP', 6), ('A2', 'VIP', 6),
('B1', 'PREMIUM', 6), ('B2', 'PREMIUM', 6),
('C1', 'STANDARD', 6), ('C2', 'STANDARD', 6);

-- Initialize tickets for all seat-showtime combinations as AVAILABLE
INSERT INTO Ticket (showtime_id, seat_id, booking_status, price)
SELECT s.showtime_id, seat.seat_id, 'AVAILABLE',
    CASE 
        WHEN seat.seat_type = 'VIP' THEN 25.00
        WHEN seat.seat_type = 'PREMIUM' THEN 18.00
        ELSE 12.00
    END as price
FROM Showtime s
CROSS JOIN Seat seat
WHERE s.theatre_id = seat.theatre_id;

-- Book some sample tickets (marking them as SOLD)
UPDATE Ticket SET 
    booking_status = 'SOLD',
    customer_email = 'john.doe@email.com',
    purchase_timestamp = NOW()
WHERE showtime_id = 1 AND seat_id IN (1, 2);

UPDATE Ticket SET 
    booking_status = 'SOLD',
    customer_email = 'jane.smith@email.com',
    purchase_timestamp = NOW()
WHERE showtime_id = 2 AND seat_id IN (4, 5);

UPDATE Ticket SET 
    booking_status = 'RESERVED',
    customer_email = 'bob.wilson@email.com',
    purchase_timestamp = NOW()
WHERE showtime_id = 3 AND seat_id = 10;

-- ================================================================================
-- SECTION 4: POST-CREATE (INDEXES)
-- ================================================================================

-- Composite index for querying tickets by showtime and status
-- This helps with the common query pattern: "Show me available seats for a specific showtime"
CREATE INDEX idx_showtime_status ON Ticket(showtime_id, booking_status);

-- Composite index for finding showtimes by date and theatre
-- This helps with: "What movies are showing at this theatre on this date?"
CREATE INDEX idx_theatre_date ON Showtime(theatre_id, show_date, start_time);

-- ================================================================================
-- SECTION 5: VERIFICATION BLOCK
-- ================================================================================

-- Evidence Query 1: Verify that users cannot buy tickets for seats already bought
-- This query shows all sold seats for a specific showtime
-- Expected: Should return seats that are marked as SOLD and cannot be purchased again
SELECT 
    t.ticket_id,
    t.showtime_id,
    s.seat_location,
    t.booking_status,
    t.customer_email,
    m.title AS movie_title,
    sh.show_date,
    sh.start_time
FROM Ticket t
JOIN Seat s ON t.seat_id = s.seat_id
JOIN Showtime sh ON t.showtime_id = sh.showtime_id
JOIN Movie m ON sh.movie_id = m.movie_id
WHERE t.showtime_id = 1 AND t.booking_status = 'SOLD'
ORDER BY s.seat_location;

-- Evidence Query 2: Verify that an auditorium cannot show two movies at the same time
-- This query checks for any overlapping showtimes in the same theatre
-- Expected: Should return 0 rows (no overlapping showtimes)
SELECT 
    s1.showtime_id AS showtime1_id,
    s2.showtime_id AS showtime2_id,
    s1.theatre_id,
    m1.title AS movie1_title,
    s1.show_date AS date1,
    s1.start_time AS start1,
    s1.end_time AS end1,
    m2.title AS movie2_title,
    s2.start_time AS start2,
    s2.end_time AS end2
FROM Showtime s1
JOIN Showtime s2 ON s1.theatre_id = s2.theatre_id 
    AND s1.show_date = s2.show_date 
    AND s1.showtime_id < s2.showtime_id
JOIN Movie m1 ON s1.movie_id = m1.movie_id
JOIN Movie m2 ON s2.movie_id = m2.movie_id
WHERE (s1.start_time < s2.end_time AND s1.end_time > s2.start_time);

-- Evidence Query 3: Verify available seats query for a selected movie, theatre, and showtime
-- This shows all available seats for a specific showtime
-- Expected: Should show seats that are AVAILABLE for purchase
SELECT 
    m.title AS movie_title,
    v.venue_name,
    th.theatre_name,
    sh.show_date,
    sh.start_time,
    s.seat_location,
    s.seat_type,
    t.price,
    t.booking_status
FROM Ticket t
JOIN Seat s ON t.seat_id = s.seat_id
JOIN Showtime sh ON t.showtime_id = sh.showtime_id
JOIN Movie m ON sh.movie_id = m.movie_id
JOIN Theatre th ON sh.theatre_id = th.theatre_id
JOIN Venue v ON th.venue_id = v.venue_id
WHERE t.showtime_id = 1 
    AND t.booking_status = 'AVAILABLE'
ORDER BY s.seat_location;

-- Additional verification: Show summary of seat availability per showtime
SELECT 
    movie_title,
    venue_name,
    theatre_name,
    show_date,
    start_time,
    available_count,
    total_capacity,
    CONCAT(ROUND((available_count/total_capacity) * 100, 1), '%') AS availability_percentage
FROM Available_Seats
WHERE show_date >= CURDATE()
ORDER BY show_date, start_time;

-- Test stored procedure for checking seat availability
CALL CheckSeatAvailability(1, 1, @is_available);
SELECT @is_available AS seat_1_available_for_showtime_1;

CALL CheckSeatAvailability(1, 3, @is_available);
SELECT @is_available AS seat_3_available_for_showtime_1;

-- ================================================================================
-- SECTION 6: SESSION RESTORE
-- ================================================================================
SET FOREIGN_KEY_CHECKS = 1;
