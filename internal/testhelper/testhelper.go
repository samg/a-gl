package testhelper

import (
	"errors"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path"
	"regexp"
	"runtime"
	"testing"
)

func AssertResponseCode(t *testing.T, response *httptest.ResponseRecorder, expectedCode int) {
	if response.Code != expectedCode {
		t.Fatalf("for HTTP request expected to get %d, got %d instead", expectedCode, response.Code)
	}
}

func AssertResponseBody(t *testing.T, response *httptest.ResponseRecorder, expectedBody string) {
	if response.Body.String() != expectedBody {
		t.Fatalf("for HTTP request expected to receive %q, got %q instead as body", expectedBody, response.Body.String())
	}
}

func AssertResponseHeader(t *testing.T, response *httptest.ResponseRecorder, header string, expectedValue string) {
	if response.Header().Get(header) != expectedValue {
		t.Fatalf("for HTTP request expected to receive the header %q with %q, got %q", header, expectedValue, response.Header().Get(header))
	}
}

func TestServerWithHandler(url *regexp.Regexp, handler http.HandlerFunc) *httptest.Server {
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if url != nil && !url.MatchString(r.URL.Path) {
			log.Println("UPSTREAM", r.Method, r.URL, "DENY")
			w.WriteHeader(404)
			return
		}

		if version := r.Header.Get("Gitlab-Workhorse"); version == "" {
			log.Println("UPSTREAM", r.Method, r.URL, "DENY")
			w.WriteHeader(403)
			return
		}

		handler(w, r)
	}))
}

func BuildExecutables() (func(), error) {
	_, currentFile, _, ok := runtime.Caller(0)
	if !ok {
		return nil, errors.New("BuildExecutables: calling runtime.Caller failed")
	}
	rootDir := path.Join(path.Dir(currentFile), "../..")

	// This method will be invoked more than once due to Go test
	// parallelization. We must use a unique temp directory for each
	// invokation so that they do not trample each other's builds.
	testDir, err := ioutil.TempDir("", "gitlab-workhorse-test")
	if err != nil {
		return nil, errors.New("could not create temp directory")
	}

	makeCmd := exec.Command("make", "BUILD_DIR="+testDir)
	makeCmd.Dir = rootDir
	makeCmd.Stderr = os.Stderr
	makeCmd.Stdout = os.Stdout
	if err := makeCmd.Run(); err != nil {
		return nil, fmt.Errorf("failed to run %v in %v", makeCmd, rootDir)
	}

	oldPath := os.Getenv("PATH")
	testPath := fmt.Sprintf("%s:%s", testDir, oldPath)
	if err := os.Setenv("PATH", testPath); err != nil {
		return nil, fmt.Errorf("failed to set PATH to %v", testPath)
	}

	return func() {
		os.Setenv("PATH", oldPath)
		os.RemoveAll(testDir)
	}, nil
}
