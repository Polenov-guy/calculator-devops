package main

import (
	"encoding/json"
	"math"
	"net/http"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
)

func TestEvaluate(t *testing.T) {
	for _, tc := range []struct {
		c    calculation
		want float64
		bad  bool
	}{{calculation{2, 3, "add"}, 5, false}, {calculation{-2, 3, "subtract"}, -5, false}, {calculation{1.5, 2, "multiply"}, 3, false}, {calculation{9, 2, "divide"}, 4.5, false}, {calculation{1, 0, "divide"}, 0, true}, {calculation{1, 2, "unknown"}, 0, true}, {calculation{math.MaxFloat64, 2, "multiply"}, 0, true}} {
		got, _, err := evaluate(tc.c)
		if (err != nil) != tc.bad || !tc.bad && got != tc.want {
			t.Fatalf("%+v: got %v %v", tc, got, err)
		}
	}
}
func TestAPIAndPersistence(t *testing.T) {
	path := filepath.Join(t.TempDir(), "app.db")
	db, err := openDB(path)
	if err != nil {
		t.Fatal(err)
	}
	a := &app{db: db}
	h := a.handler()
	request := func(method, url, body string, cookie *http.Cookie) *httptest.ResponseRecorder {
		r := httptest.NewRequest(method, url, strings.NewReader(body))
		r.Header.Set("Content-Type", "application/json")
		if cookie != nil {
			r.AddCookie(cookie)
		}
		w := httptest.NewRecorder()
		h.ServeHTTP(w, r)
		return w
	}
	w := request("GET", "/", "", nil)
	if w.Code != 200 {
		t.Fatal(w.Code)
	}
	cookie := w.Result().Cookies()[0]
	w = request("POST", "/api/calculate", `{"a":7,"b":3,"operation":"multiply"}`, cookie)
	if w.Code != 200 {
		t.Fatal(w.Body.String())
	}
	if a.views.Load() != 1 || a.success[2].Load() != 1 {
		t.Fatal("wrong metrics")
	}
	for _, body := range []string{`{"a":1,"b":0,"operation":"divide"}`, `{"a":1,"b":2,"operation":"add","x":1}`, `{"a":1} {}`, `{"a":1e400}`, `{"a":null,"b":1,"operation":"add"}`, `{"b":1,"operation":"add"}`} {
		if w = request("POST", "/api/calculate", body, cookie); w.Code != 400 {
			t.Fatal(w.Code, body)
		}
	}
	if w = request("GET", "/api/history", "", nil); w.Body.String() != "[]\n" {
		t.Fatal("session leak", w.Body.String())
	}
	db.Close()
	db, err = openDB(path)
	if err != nil {
		t.Fatal(err)
	}
	defer db.Close()
	a.db = db
	w = request("GET", "/api/history", "", cookie)
	var entries []entry
	if err = json.Unmarshal(w.Body.Bytes(), &entries); err != nil || len(entries) != 1 || entries[0].Result != 21 {
		t.Fatal(w.Body.String(), err)
	}
	if w = request("GET", "/metrics", "", nil); !strings.Contains(w.Body.String(), "calculator_page_views_total 1") {
		t.Fatal(w.Body.String())
	}
	if w = request("GET", "/readyz", "", nil); w.Code != 200 {
		t.Fatal(w.Code)
	}
	db.Close()
	if w = request("GET", "/readyz", "", nil); w.Code != 503 {
		t.Fatal(w.Code)
	}
}
