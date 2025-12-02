-- Team Name: SQL Nerds
-- Members: Ivan Lerma, Logan Ferris, Gage Johnson, Nick Sanchez, Abhinav Raj Gupta, Sarthak Dudhani

SET sql_mode = 'STRICT_TRANS_TABLES,ONLY_FULL_GROUP_BY';
SET FOREIGN_KEY_CHECKS = 0;

DROP DATABASE IF EXISTS movie_theater_system;
CREATE DATABASE movie_theater_system;
USE movie_theater_system;

DROP TABLE IF EXISTS Ticket;
DROP TABLE IF EXISTS Seat_Showtime;
DROP TABLE IF EXISTS Seat;
DROP TABLE IF EXISTS Showtime;
DROP TABLE IF EXISTS Movie;
DROP TABLE IF EXISTS Theatre;
DROP TABLE IF EXISTS Venue;

CREATE TABLE Venue (
    venue_id INT AUTO_INCREMENT PRIMARY KEY,
    venue_name VARCHAR(100) NOT NULL,
    address VARCHAR(255) NOT NULL,
    UNIQUE KEY unique_venue_address (venue_name, address)
);

CREATE TABLE Theatre (
    theatre_id INT AUTO_INCREMENT PRIMARY KEY,
    theatre_name VARCHAR(50) NOT NULL,
    capacity INT NOT NULL CHECK (capacity > 0),
    venue_id INT NOT NULL,
    FOREIGN KEY (venue_id) REFERENCES Venue(venue_id) ON DELETE CASCADE,
    INDEX idx_venue_theatre (venue_id),
    UNIQUE KEY unique_theatre_per_venue (venue_id, theatre_name)
);

CREATE TABLE Movie (
    movie_id INT AUTO_INCREMENT PRIMARY KEY,
    title VARCHAR(200) NOT NULL,
    genre VARCHAR(50) NOT NULL,
    duration INT NOT NULL CHECK (duration > 0),
    release_year INT NOT NULL CHECK (release_year >= 1900 AND release_year <= 2100),
    rating VARCHAR(10) NOT NULL CHECK (rating IN ('G', 'PG', 'PG-13', 'R', 'NC-17')),
    description TEXT,
    INDEX idx_movie_title (title),
    INDEX idx_movie_genre_year (genre, release_year)
);

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
    UNIQUE KEY unique_theatre_showtime (theatre_id, show_date, start_time),
    CHECK (end_time > start_time)
);

CREATE TABLE Seat (
    seat_id INT AUTO_INCREMENT PRIMARY KEY,
    seat_location VARCHAR(10) NOT NULL,
    seat_type VARCHAR(20) DEFAULT 'STANDARD',
    theatre_id INT NOT NULL,
    FOREIGN KEY (theatre_id) REFERENCES Theatre(theatre_id) ON DELETE CASCADE,
    UNIQUE KEY unique_seat_per_theatre (theatre_id, seat_location),
    INDEX idx_theatre_seats (theatre_id)
);

-- NEW: explicit bridge to avoid chasm trap
CREATE TABLE Seat_Showtime (
    seat_showtime_id INT AUTO_INCREMENT PRIMARY KEY,
    showtime_id INT NOT NULL,
    seat_id INT NOT NULL,
    FOREIGN KEY (showtime_id) REFERENCES Showtime(showtime_id) ON DELETE CASCADE,
    FOREIGN KEY (seat_id) REFERENCES Seat(seat_id) ON DELETE CASCADE,
    UNIQUE KEY unique_showtime_seat (showtime_id, seat_id),
    INDEX idx_seat_showtime_showtime (showtime_id),
    INDEX idx_seat_showtime_seat (seat_id)
);

-- Ticket now references Seat_Showtime
CREATE TABLE Ticket (
    ticket_id INT AUTO_INCREMENT PRIMARY KEY,
    seat_showtime_id INT NOT NULL,
    booking_status VARCHAR(20) NOT NULL DEFAULT 'AVAILABLE'
        CHECK (booking_status IN ('AVAILABLE', 'RESERVED', 'SOLD')),
    price DECIMAL(6,2) NOT NULL CHECK (price >= 0),
    purchase_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    customer_email VARCHAR(100),
    FOREIGN KEY (seat_showtime_id) REFERENCES Seat_Showtime(seat_showtime_id) ON DELETE CASCADE,
    INDEX idx_seat_showtime (seat_showtime_id),
    INDEX idx_booking_status (booking_status)
);

-- View and procedural logic will reference Seat_Showtime + Ticket instead of Ticket(showtime_id, seat_id)

-- Trigger to prevent booking tickets for past showtimes (same logic, but via Seat_Showtime)
DELIMITER //
CREATE TRIGGER prevent_past_booking
BEFORE INSERT ON Ticket
FOR EACH ROW
BEGIN
    DECLARE v_showtime_id INT;
    DECLARE show_datetime DATETIME;

    SELECT showtime_id INTO v_showtime_id
    FROM Seat_Showtime
    WHERE seat_showtime_id = NEW.seat_showtime_id;

    SELECT CONCAT(show_date, ' ', start_time) INTO show_datetime
    FROM Showtime
    WHERE showtime_id = v_showtime_id;

    IF show_datetime < NOW() AND NEW.booking_status IN ('RESERVED', 'SOLD') THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Cannot book tickets for past showtimes';
    END IF;
END//
DELIMITER ;

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

-- Stored procedure rewritten to use Seat_Showtime
DELIMITER //
CREATE PROCEDURE CheckSeatAvailability(
    IN p_showtime_id INT,
    IN p_seat_id INT,
    OUT is_available BOOLEAN
)
BEGIN
    DECLARE v_seat_showtime_id INT;
    DECLARE status VARCHAR(20);

    SELECT seat_showtime_id
      INTO v_seat_showtime_id
    FROM Seat_Showtime
    WHERE showtime_id = p_showtime_id
      AND seat_id = p_seat_id
    LIMIT 1;

    IF v_seat_showtime_id IS NULL THEN
        SET is_available = FALSE;
    ELSE
        SELECT booking_status INTO status
        FROM Ticket
        WHERE seat_showtime_id = v_seat_showtime_id
        LIMIT 1;

        IF status IS NULL OR status = 'AVAILABLE' THEN
            SET is_available = TRUE;
        ELSE
            SET is_available = FALSE;
        END IF;
    END IF;
END//
DELIMITER ;

-- Seed data (Venue, Theatre, Movie, Showtime, Seat) stays the same as your original

-- After inserting Showtime and Seat rows, populate Seat_Showtime:
INSERT INTO Seat_Showtime (showtime_id, seat_id)
SELECT s.showtime_id, seat.seat_id
FROM Showtime s
JOIN Seat seat ON s.theatre_id = seat.theatre_id;

-- Initialize tickets for all seat_showtime combinations as AVAILABLE
INSERT INTO Ticket (seat_showtime_id, booking_status, price)
SELECT ss.seat_showtime_id, 'AVAILABLE',
    CASE 
        WHEN se.seat_type = 'VIP' THEN 25.00
        WHEN se.seat_type = 'PREMIUM' THEN 18.00
        ELSE 12.00
    END AS price
FROM Seat_Showtime ss
JOIN Seat se ON ss.seat_id = se.seat_id;

SET FOREIGN_KEY_CHECKS = 1;
