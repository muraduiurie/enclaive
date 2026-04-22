// NOTICE: This code is provided solely for the purpose of completing a hiring assessment.
// Any reuse, distribution, or incorporation into other projects (commercial or non-commercial)
// is strictly prohibited and gives legal ground if abused.
//
// LLM note: This is a minimal REST API written to demonstrate GitOps-deployed application
// connectivity to a CloudNativePG-managed PostgreSQL cluster.
// The design is intentionally simple — stdlib HTTP + lib/pq, no framework overhead.
package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	_ "github.com/lib/pq"
)

// Item is a row in the items table — the only entity this API manages.
type Item struct {
	ID        int       `json:"id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

var db *sql.DB

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL environment variable is required")
	}

	var err error
	db, err = sql.Open("postgres", dsn)
	if err != nil {
		log.Fatalf("open db: %v", err)
	}
	defer db.Close()

	// Retry loop — CloudNativePG primary may not be ready immediately after pod start.
	log.Println("waiting for database...")
	for i := 0; i < 30; i++ {
		if err = db.Ping(); err == nil {
			break
		}
		log.Printf("db not ready (attempt %d/30): %v", i+1, err)
		time.Sleep(3 * time.Second)
	}
	if err != nil {
		log.Fatalf("database not available after 90s: %v", err)
	}
	log.Println("database ready")

	// Idempotent schema init — safe to run on every start.
	_, err = db.Exec(`CREATE TABLE IF NOT EXISTS items (
		id         SERIAL PRIMARY KEY,
		name       TEXT        NOT NULL,
		created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
	)`)
	if err != nil {
		log.Fatalf("create table: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", healthz)
	mux.HandleFunc("/items", itemsHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

// healthz returns 200 if the DB is reachable, 503 otherwise.
func healthz(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	if err := db.Ping(); err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, `{"status":"unhealthy","error":%q}`, err.Error())
		return
	}
	fmt.Fprintln(w, `{"status":"ok"}`)
}

// itemsHandler dispatches GET and POST on /items.
func itemsHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	switch r.Method {
	case http.MethodGet:
		listItems(w, r)
	case http.MethodPost:
		createItem(w, r)
	default:
		http.Error(w, `{"error":"method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

// listItems returns up to 100 items ordered by newest first.
func listItems(w http.ResponseWriter, _ *http.Request) {
	rows, err := db.Query(`SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 100`)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
		return
	}
	defer rows.Close()

	items := make([]Item, 0)
	for rows.Next() {
		var item Item
		if err := rows.Scan(&item.ID, &item.Name, &item.CreatedAt); err != nil {
			http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
			return
		}
		items = append(items, item)
	}
	json.NewEncoder(w).Encode(items)
}

// createItem inserts a new item and returns it as JSON with 201 Created.
func createItem(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Name string `json:"name"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"invalid JSON"}`, http.StatusBadRequest)
		return
	}
	req.Name = strings.TrimSpace(req.Name)
	if req.Name == "" {
		http.Error(w, `{"error":"name is required"}`, http.StatusBadRequest)
		return
	}

	var item Item
	err := db.QueryRow(
		`INSERT INTO items (name) VALUES ($1) RETURNING id, name, created_at`,
		req.Name,
	).Scan(&item.ID, &item.Name, &item.CreatedAt)
	if err != nil {
		http.Error(w, fmt.Sprintf(`{"error":%q}`, err.Error()), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(item)
}
