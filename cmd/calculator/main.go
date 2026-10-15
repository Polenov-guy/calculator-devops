package main

import (
	"context"
	"crypto/rand"
	"database/sql"
	"embed"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"math"
	_ "modernc.org/sqlite"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

//go:embed web/*
var assets embed.FS
var version = "dev"
var builtAt = "unknown"

type app struct {
	db      *sql.DB
	views   atomic.Uint64
	success [4]atomic.Uint64
	failed  [4]atomic.Uint64
}
type calculation struct {
	A         float64 `json:"a"`
	B         float64 `json:"b"`
	Operation string  `json:"operation"`
}
type entry struct {
	ID        int64   `json:"id"`
	A         float64 `json:"a"`
	B         float64 `json:"b"`
	Operation string  `json:"operation"`
	Result    float64 `json:"result"`
	Created   string  `json:"created_at"`
}

func env(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}
func openDB(path string) (*sql.DB, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0750); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	_, err = db.Exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; PRAGMA temp_store=MEMORY;
 CREATE TABLE IF NOT EXISTS calculations(id INTEGER PRIMARY KEY, session TEXT NOT NULL,a REAL NOT NULL,b REAL NOT NULL,operation TEXT NOT NULL,result REAL NOT NULL,created_at TEXT NOT NULL);
 CREATE INDEX IF NOT EXISTS session_history ON calculations(session,id);`)
	if err != nil {
		db.Close()
		return nil, err
	}
	return db, nil
}

var operations = []string{"add", "subtract", "multiply", "divide"}

func evaluate(c calculation) (float64, int, error) {
	idx := -1
	for i, op := range operations {
		if c.Operation == op {
			idx = i
		}
	}
	if idx < 0 {
		return 0, idx, errors.New("неизвестная операция")
	}
	if math.IsNaN(c.A) || math.IsInf(c.A, 0) || math.IsNaN(c.B) || math.IsInf(c.B, 0) {
		return 0, idx, errors.New("нужно конечное число")
	}
	var r float64
	switch idx {
	case 0:
		r = c.A + c.B
	case 1:
		r = c.A - c.B
	case 2:
		r = c.A * c.B
	case 3:
		if c.B == 0 {
			return 0, idx, errors.New("деление на ноль")
		}
		r = c.A / c.B
	}
	if math.IsNaN(r) || math.IsInf(r, 0) {
		return 0, idx, errors.New("результат вне допустимого диапазона")
	}
	return r, idx, nil
}
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
func fail(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}
func session(w http.ResponseWriter, r *http.Request) string {
	if c, err := r.Cookie("calculator_session"); err == nil && len(c.Value) == 64 {
		if _, err := hex.DecodeString(c.Value); err == nil {
			return c.Value
		}
	}
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	s := hex.EncodeToString(b)
	http.SetCookie(w, &http.Cookie{Name: "calculator_session", Value: s, Path: "/", HttpOnly: true, SameSite: http.SameSiteLaxMode, Secure: r.TLS != nil || env("COOKIE_SECURE", "false") == "true", MaxAge: 60 * 60 * 24 * 30})
	return s
}
func (a *app) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) { writeJSON(w, 200, map[string]string{"status": "ok"}) })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()
		if err := a.db.PingContext(ctx); err != nil {
			fail(w, 503, "database unavailable")
			return
		}
		writeJSON(w, 200, map[string]string{"status": "ready"})
	})
	mux.HandleFunc("GET /version", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, 200, map[string]string{"version": version, "built_at": builtAt})
	})
	mux.HandleFunc("GET /metrics", a.metrics)
	mux.HandleFunc("POST /api/calculate", func(w http.ResponseWriter, r *http.Request) {
		// Reject cross-site browser requests before issuing a session cookie.
		if r.Header.Get("Sec-Fetch-Site") == "cross-site" {
			fail(w, 403, "cross-site request rejected")
			return
		}
		if !strings.HasPrefix(r.Header.Get("Content-Type"), "application/json") {
			fail(w, 415, "нужен application/json")
			return
		}
		r.Body = http.MaxBytesReader(w, r.Body, 4096)
		d := json.NewDecoder(r.Body)
		d.DisallowUnknownFields()
		var input struct {
			A         *float64 `json:"a"`
			B         *float64 `json:"b"`
			Operation string   `json:"operation"`
		}
		if err := d.Decode(&input); err != nil {
			fail(w, 400, "некорректный JSON")
			return
		}
		if err := d.Decode(&struct{}{}); err != io.EOF {
			fail(w, 400, "лишние данные")
			return
		}
		if input.A == nil || input.B == nil {
			fail(w, 400, "оба числа обязательны")
			return
		}
		c := calculation{*input.A, *input.B, input.Operation}
		result, idx, err := evaluate(c)
		if err != nil {
			if idx >= 0 {
				a.failed[idx].Add(1)
			}
			fail(w, 400, err.Error())
			return
		}
		sid := session(w, r)
		now := time.Now().UTC().Format(time.RFC3339)
		tx, err := a.db.BeginTx(r.Context(), nil)
		if err != nil {
			fail(w, 503, "ошибка хранения")
			return
		}
		defer tx.Rollback()
		res, err := tx.ExecContext(r.Context(), "INSERT INTO calculations(session,a,b,operation,result,created_at) VALUES(?,?,?,?,?,?)", sid, c.A, c.B, c.Operation, result, now)
		if err == nil {
			_, err = tx.ExecContext(r.Context(), "DELETE FROM calculations WHERE session=? AND id NOT IN (SELECT id FROM calculations WHERE session=? ORDER BY id DESC LIMIT 100)", sid, sid)
		}
		if err == nil {
			_, err = tx.ExecContext(r.Context(), "DELETE FROM calculations WHERE created_at < ?", time.Now().AddDate(0, 0, -30).UTC().Format(time.RFC3339))
		}
		if err != nil {
			log.Print(err)
			fail(w, 503, "ошибка сохранения")
			return
		}
		id, _ := res.LastInsertId()
		if err = tx.Commit(); err != nil {
			fail(w, 503, "ошибка сохранения")
			return
		}
		a.success[idx].Add(1)
		writeJSON(w, 200, entry{id, c.A, c.B, c.Operation, result, now})
	})
	mux.HandleFunc("GET /api/history", func(w http.ResponseWriter, r *http.Request) {
		sid := session(w, r)
		rows, err := a.db.QueryContext(r.Context(), "SELECT id,a,b,operation,result,created_at FROM calculations WHERE session=? ORDER BY id DESC LIMIT 100", sid)
		if err != nil {
			fail(w, 503, "ошибка чтения")
			return
		}
		defer rows.Close()
		list := []entry{}
		for rows.Next() {
			var e entry
			if err = rows.Scan(&e.ID, &e.A, &e.B, &e.Operation, &e.Result, &e.Created); err != nil {
				fail(w, 503, "ошибка чтения")
				return
			}
			list = append(list, e)
		}
		if rows.Err() != nil {
			fail(w, 503, "ошибка чтения")
			return
		}
		writeJSON(w, 200, list)
	})
	files, _ := fs.Sub(assets, "web")
	static := http.FileServer(http.FS(files))
	mux.HandleFunc("GET /", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" && r.Method == http.MethodGet {
			session(w, r)
			a.views.Add(1)
			w.Header().Set("Cache-Control", "no-store")
		}
		static.ServeHTTP(w, r)
	})
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; style-src 'self'; script-src 'self'; frame-ancestors 'none'")
		mux.ServeHTTP(w, r)
	})
}
func (a *app) metrics(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
	fmt.Fprintf(w, "# HELP calculator_page_views_total Successful page openings.\n# TYPE calculator_page_views_total counter\ncalculator_page_views_total %d\n", a.views.Load())
	fmt.Fprint(w, "# HELP calculator_calculations_total Valid calculation requests by outcome.\n# TYPE calculator_calculations_total counter\n")
	for i, op := range operations {
		fmt.Fprintf(w, "calculator_calculations_total{operation=%q,status=\"success\"} %d\ncalculator_calculations_total{operation=%q,status=\"error\"} %d\n", op, a.success[i].Load(), op, a.failed[i].Load())
	}
	fmt.Fprintf(w, "# HELP calculator_build_info Build identity.\n# TYPE calculator_build_info gauge\ncalculator_build_info{version=%q} 1\n", version)
}
func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		client := http.Client{Timeout: 3 * time.Second}
		resp, err := client.Get("http://127.0.0.1:8080/readyz")
		if err != nil {
			os.Exit(1)
		}
		resp.Body.Close()
		if resp.StatusCode != 200 {
			os.Exit(1)
		}
		return
	}
	if len(os.Args) > 2 && os.Args[1] == "backup" {
		db, err := openDB(env("DB_PATH", "/data/calculator.db"))
		if err != nil {
			log.Fatal(err)
		}
		defer db.Close()
		if err := os.Remove(os.Args[2]); err != nil && !os.IsNotExist(err) {
			log.Fatal(err)
		}
		target := strings.ReplaceAll(os.Args[2], "'", "''")
		if _, err = db.Exec("VACUUM INTO '" + target + "'"); err != nil {
			log.Fatal(err)
		}
		return
	}
	db, err := openDB(env("DB_PATH", "./data/calculator.db"))
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()
	a := &app{db: db}
	server := &http.Server{Addr: env("LISTEN_ADDR", ":8080"), Handler: a.handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 15 * time.Second, IdleTimeout: 60 * time.Second, MaxHeaderBytes: 16384}
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		log.Printf("calculator version=%s listening=%s", version, server.Addr)
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatal(err)
		}
	}()
	<-stop
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = server.Shutdown(ctx)
}
