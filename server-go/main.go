package main

import (
	"bytes"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	acpSchemaVersion        = "meshkit-acp-superapp/v1"
	memorySchemaVersion     = "meshkit-preference-memory/v1"
	routingSchemaVersion    = "meshkit-execution-routing/v1"
	settlementSchemaVersion = "meshkit-settlement-ledger/v1"
	storeSchemaVersion      = "meshkit-superapp-store/v1"
	defaultUserID           = "local-user"
	defaultAgentID          = "agent.meshkit-superapp"
	nowISO                  = "2026-06-08T00:00:00.000Z"
	requestBodyLimitBytes   = 1 << 20
)

type AppDescriptor struct {
	SchemaVersion                 string         `json:"schemaVersion"`
	AppID                         string         `json:"appId"`
	OcgAppID                      string         `json:"ocgAppId"`
	DisplayName                   string         `json:"displayName"`
	Publisher                     string         `json:"publisher"`
	AcpEndpoint                   string         `json:"acpEndpoint"`
	MCPTransport                  string         `json:"mcpTransport"`
	BundleID                      string         `json:"bundleId"`
	Platform                      string         `json:"platform"`
	PackageName                   string         `json:"packageName,omitempty"`
	Verified                      bool           `json:"verified,omitempty"`
	RegistrySource                string         `json:"registrySource"`
	Trust                         any            `json:"trust,omitempty"`
	RegistrySignature             any            `json:"registrySignature,omitempty"`
	RegistrySignatureVerification map[string]any `json:"registrySignatureVerification,omitempty"`
	Capabilities                  []Capability   `json:"capabilities"`
}

type Capability struct {
	ID              string         `json:"id"`
	DisplayName     string         `json:"displayName"`
	Version         string         `json:"version,omitempty"`
	Description     string         `json:"description,omitempty"`
	Risk            string         `json:"risk"`
	Consent         string         `json:"consent"`
	RequiresPayment bool           `json:"requiresPayment"`
	Asset           any            `json:"asset"`
	URLScheme       string         `json:"urlScheme"`
	InputSchema     []string       `json:"inputSchema"`
	ResultSchema    []string       `json:"resultSchema"`
	RoutingHint     string         `json:"routingHint"`
	OCG             map[string]any `json:"ocg,omitempty"`
}

type PreferenceEvent struct {
	ID             string         `json:"id"`
	Key            string         `json:"key"`
	UserID         string         `json:"userId"`
	AgentID        string         `json:"agentId"`
	Role           string         `json:"role"`
	Kind           string         `json:"kind"`
	Content        string         `json:"content"`
	Value          string         `json:"value"`
	Source         string         `json:"source"`
	Signals        map[string]any `json:"signals"`
	CreatedAt      string         `json:"createdAt"`
	UpdatedAt      string         `json:"updatedAt"`
	LastAccessedAt string         `json:"lastAccessedAt"`
	AccessCount    int            `json:"accessCount"`
}

type MemoryEntry struct {
	SchemaVersion   string         `json:"schemaVersion"`
	MemoryID        string         `json:"memoryId"`
	Key             string         `json:"key"`
	UserID          string         `json:"userId"`
	AgentID         string         `json:"agentId"`
	MemoryKind      string         `json:"memoryKind"`
	Value           string         `json:"value"`
	Content         string         `json:"content"`
	Source          string         `json:"source"`
	CreatedAt       string         `json:"createdAt"`
	UpdatedAt       string         `json:"updatedAt"`
	LastAccessedAt  string         `json:"lastAccessedAt"`
	AccessCount     int            `json:"accessCount"`
	Importance      float64        `json:"importance"`
	Signals         map[string]any `json:"signals"`
	Metadata        map[string]any `json:"metadata"`
	PromotedAt      string         `json:"promotedAt,omitempty"`
	PromotionReason string         `json:"promotionReason,omitempty"`
	RetrievalScore  float64        `json:"retrievalScore,omitempty"`
}

type PreferenceMemory struct {
	SchemaVersion  string           `json:"schemaVersion"`
	UserID         string           `json:"userId"`
	AgentID        string           `json:"agentId"`
	WorkingMemory  []MemoryEntry    `json:"workingMemory"`
	PromotedMemory []MemoryEntry    `json:"promotedMemory"`
	FilteredEvents []map[string]any `json:"filteredEvents"`
	DroppedEvents  []map[string]any `json:"droppedEvents"`
	Consolidation  map[string]any   `json:"consolidation"`
}

type RoutingPolicy struct {
	PolicyID            string   `json:"policyId"`
	Source              string   `json:"source"`
	SourceMemoryIDs     []string `json:"sourceMemoryIds"`
	PaymentProof        string   `json:"paymentProof"`
	NonPaymentTransport string   `json:"nonPaymentTransport"`
	PayloadPrivacy      string   `json:"payloadPrivacy"`
	ChainVisibleFields  []string `json:"chainVisibleFields"`
	OffchainFields      []string `json:"offchainFields"`
	DecisionReason      string   `json:"decisionReason"`
}

type RouteDecision struct {
	SchemaVersion      string        `json:"schemaVersion"`
	Route              string        `json:"route"`
	Transport          string        `json:"transport"`
	AppID              string        `json:"appId"`
	CapabilityID       string        `json:"capabilityId"`
	RequiresPayment    bool          `json:"requiresPayment"`
	Asset              any           `json:"asset"`
	Amount             float64       `json:"amount"`
	PrivacyBoundary    string        `json:"privacyBoundary"`
	RecalledPreference []MemoryEntry `json:"recalledPreferences"`
	AppliedPolicy      RoutingPolicy `json:"appliedPolicy"`
}

type TransactionRecord struct {
	SchemaVersion         string        `json:"schemaVersion"`
	Route                 string        `json:"route"`
	RecordType            string        `json:"recordType"`
	RequestID             string        `json:"requestId"`
	UserID                string        `json:"userId"`
	AgentID               string        `json:"agentId"`
	AppID                 string        `json:"appId"`
	CapabilityID          string        `json:"capabilityId"`
	Provider              string        `json:"provider,omitempty"`
	Network               string        `json:"network,omitempty"`
	Asset                 string        `json:"asset,omitempty"`
	Amount                float64       `json:"amount"`
	Status                string        `json:"status"`
	TxHash                string        `json:"txHash"`
	ExplorerURL           string        `json:"explorerUrl,omitempty"`
	PolicyHash            string        `json:"policyHash,omitempty"`
	SignedRequestHash     string        `json:"signedRequestHash"`
	OffchainRecordID      string        `json:"offchainRecordId,omitempty"`
	AppliedPolicy         RoutingPolicy `json:"appliedPolicy"`
	PolicySourceMemoryIDs []string      `json:"policySourceMemoryIds"`
	ChainVisibleFields    []string      `json:"chainVisibleFields"`
	OffchainFields        []string      `json:"offchainFields"`
	CreatedAt             string        `json:"createdAt"`
}

type SettlementLedger struct {
	SchemaVersion string           `json:"schemaVersion"`
	GeneratedAt   string           `json:"generatedAt"`
	Entries       []map[string]any `json:"entries"`
	Summary       map[string]any   `json:"summary"`
}

type StoreState struct {
	SchemaVersion    string              `json:"schemaVersion"`
	PreferenceEvents []PreferenceEvent   `json:"preferenceEvents"`
	ExecutionRecords []TransactionRecord `json:"executionRecords"`
}

type AppServer struct {
	dataDir     string
	registryDir string
	staticDir   string
	mu          sync.Mutex
	clock       func() string
	httpClient  *http.Client
}

func main() {
	root, err := os.Getwd()
	if err != nil {
		panic(err)
	}
	repoRoot := filepath.Dir(root)
	port := envOr("PORT", "4173")
	server := NewAppServer(
		envOr("MESHKIT_SUPERAPP_DATA_DIR", filepath.Join(root, ".meshkit-data")),
		envOr("MESHKIT_ACP_REGISTRY_DIR", filepath.Join(repoRoot, "ocg", "registry")),
		envOr("MESHKIT_SUPERAPP_STATIC_DIR", filepath.Join(repoRoot, "web", "src")),
	)
	fmt.Printf("MeshKit Go superapp server running at http://localhost:%s\n", port)
	if err := http.ListenAndServe(":"+port, server.Routes()); err != nil {
		panic(err)
	}
}

func NewAppServer(dataDir, registryDir, staticDir string) *AppServer {
	return &AppServer{dataDir: dataDir, registryDir: registryDir, staticDir: staticDir, clock: func() string { return nowISO }}
}

func (s *AppServer) now() string {
	if s.clock == nil {
		return nowISO
	}
	return s.clock()
}

func envOr(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func (s *AppServer) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/superapp-state", s.handleSuperappState)
	mux.HandleFunc("/api/acp/apps", s.handleAcpApps)
	mux.HandleFunc("/api/agent-chat", s.handleAgentChat)
	mux.HandleFunc("/api/preferences", s.handlePreferences)
	mux.HandleFunc("/api/execute", s.handleExecute)
	mux.HandleFunc("/api/settlements", s.handleSettlements)
	mux.HandleFunc("/api/trust-paths", s.handleTrustPaths)
	mux.HandleFunc("/", s.handleStatic)
	return mux
}

type AgentChatMessage struct {
	Role       string           `json:"role"`
	Content    string           `json:"content,omitempty"`
	ToolCallID string           `json:"tool_call_id,omitempty"`
	ToolCalls  []OpenAIToolCall `json:"tool_calls,omitempty"`
}

type OpenAIToolCall struct {
	ID       string `json:"id"`
	Type     string `json:"type"`
	Function struct {
		Name      string `json:"name"`
		Arguments string `json:"arguments"`
	} `json:"function"`
}

type OpenAIChatResponse struct {
	Choices []struct {
		Message AgentChatMessage `json:"message"`
	} `json:"choices"`
	Error map[string]any `json:"error,omitempty"`
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("content-type", "application/json; charset=utf-8")
	w.Header().Set("cache-control", "no-store")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func apiError(w http.ResponseWriter, status int, err error) {
	writeJSON(w, status, map[string]any{"error": "api_error", "message": err.Error()})
}

func readJSON(w http.ResponseWriter, r *http.Request) (map[string]any, error) {
	if r.Body == nil {
		return map[string]any{}, nil
	}
	defer r.Body.Close()
	r.Body = http.MaxBytesReader(w, r.Body, requestBodyLimitBytes)
	body, err := io.ReadAll(r.Body)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			return nil, maxBytesErr
		}
		return nil, err
	}
	if len(bytes.TrimSpace(body)) == 0 {
		return map[string]any{}, nil
	}
	var payload map[string]any
	if err := json.Unmarshal(body, &payload); err != nil {
		return nil, errors.New("request body must be valid JSON")
	}
	return payload, nil
}

func (s *AppServer) handleAcpApps(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
		return
	}
	discovery := s.loadAcpDiscovery()
	writeJSON(w, http.StatusOK, map[string]any{
		"schemaVersion": "meshkit-acp-discovery-response/v1",
		"registryMode":  discovery.RegistryMode,
		"registryDir":   discovery.RegistryDir,
		"registryFiles": discovery.RegistryFiles,
		"registryTrust": discovery.RegistryTrust,
		"registryError": discovery.RegistryError,
		"apps":          discovery.Apps,
	})
}

func (s *AppServer) handleSuperappState(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
		return
	}
	discovery := s.loadAcpDiscovery()
	state, err := s.readPersistentSuperappState(discovery.Apps)
	if err != nil {
		apiError(w, http.StatusBadRequest, err)
		return
	}
	state["acpDiscovery"] = map[string]any{
		"registryMode":  discovery.RegistryMode,
		"registryDir":   discovery.RegistryDir,
		"registryFiles": discovery.RegistryFiles,
		"registryTrust": discovery.RegistryTrust,
		"registryError": discovery.RegistryError,
	}
	state["apiMode"] = "go-local-deterministic-superapp-state"
	writeJSON(w, http.StatusOK, state)
}

func (s *AppServer) handleAgentChat(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
		return
	}
	apiKey := strings.TrimSpace(os.Getenv("OPENAI_API_KEY"))
	if apiKey == "" {
		apiError(w, http.StatusServiceUnavailable, errors.New("OPENAI_API_KEY is required for live agent chat"))
		return
	}
	body, err := readJSON(w, r)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			apiError(w, http.StatusRequestEntityTooLarge, errors.New("request body exceeds 1 MiB limit"))
			return
		}
		apiError(w, http.StatusBadRequest, err)
		return
	}
	userMessages, err := parseAgentChatMessages(body)
	if err != nil {
		apiError(w, http.StatusBadRequest, err)
		return
	}
	discovery := s.loadAcpDiscovery()
	if discovery.RegistryMode != "signed-ocg-registry" {
		apiError(w, http.StatusBadRequest, errors.New("agent chat requires signed ACP discovery"))
		return
	}
	messages := []AgentChatMessage{{
		Role: "system",
		Content: strings.Join([]string{
			"You are the MeshKit superapp agent in a real multi-turn conversation.",
			"Use only tools generated from live /api/acp/apps discovery.",
			"Save durable user preferences with remember_preference when the user asks you to remember something.",
			"Use notes.append_note for note requests with amount 0.",
			"Use grocery.purchase_essentials for DailyMart grocery purchases with amount 42 unless the user states a different OKRW amount.",
			"After paid purchases, call get_settlement_ledger before giving the final answer.",
			"Be concise and report only executed results and relevant discovered capabilities.",
			"Do not add unsolicited follow-up offers such as 'if you want' or 'I can also'.",
			"Live ACP discovery summary: " + mustJSON(discoverySummaryForAgent(discovery.Apps)),
		}, " "),
	}}
	messages = append(messages, userMessages...)
	tools := append(agentCapabilityTools(discovery.Apps), agentSupportTools()...)
	toolResults := []map[string]any{}
	for turn := 0; turn < 6; turn++ {
		message, err := s.openAIChatCompletion(apiKey, messages, tools)
		if err != nil {
			apiError(w, http.StatusBadGateway, err)
			return
		}
		messages = append(messages, message)
		if len(message.ToolCalls) == 0 {
			state, stateErr := s.readPersistentSuperappState(discovery.Apps)
			if stateErr != nil {
				apiError(w, http.StatusBadRequest, stateErr)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{
				"schemaVersion":  "meshkit-agent-chat-response/v1",
				"conversationId": defaultString(firstString(body, "conversationId", "conversation_id"), "local-agent-chat"),
				"assistant":      map[string]any{"role": message.Role, "content": message.Content},
				"messages":       messages,
				"toolResults":    toolResults,
				"state":          state,
			})
			return
		}
		for _, call := range message.ToolCalls {
			result, err := s.executeAgentToolCall(call, discovery.Apps)
			if err != nil {
				apiError(w, http.StatusBadRequest, err)
				return
			}
			toolResults = append(toolResults, map[string]any{"name": call.Function.Name, "result": result})
			messages = append(messages, AgentChatMessage{Role: "tool", ToolCallID: call.ID, Content: mustJSON(result)})
		}
	}
	apiError(w, http.StatusBadGateway, errors.New("agent chat did not finish within 6 tool-call turns"))
}

func (s *AppServer) handlePreferences(w http.ResponseWriter, r *http.Request) {
	discovery := s.loadAcpDiscovery()
	switch r.Method {
	case http.MethodGet:
		limit := 10
		if raw := r.URL.Query().Get("limit"); raw != "" {
			if parsed, err := strconv.Atoi(raw); err == nil && parsed > 0 {
				limit = parsed
			}
		}
		preferences, err := s.queryPreferences(r.URL.Query().Get("query"), limit, discovery.Apps)
		if err != nil {
			apiError(w, http.StatusBadRequest, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"schemaVersion": "meshkit-preference-query-response/v1",
			"preferences":   preferences,
		})
	case http.MethodPost:
		body, err := readJSON(w, r)
		if err != nil {
			var maxBytesErr *http.MaxBytesError
			if errors.As(err, &maxBytesErr) {
				apiError(w, http.StatusRequestEntityTooLarge, errors.New("request body exceeds 1 MiB limit"))
				return
			}
			apiError(w, http.StatusBadRequest, err)
			return
		}
		result, err := s.upsertPreference(body, discovery.Apps)
		if err != nil {
			apiError(w, http.StatusBadRequest, err)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{
			"schemaVersion":     "meshkit-preference-upsert-response/v1",
			"preference":        result["preference"],
			"droppedPreference": result["droppedPreference"],
			"state":             result["state"],
		})
	default:
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
	}
}

func (s *AppServer) handleExecute(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
		return
	}
	body, err := readJSON(w, r)
	if err != nil {
		var maxBytesErr *http.MaxBytesError
		if errors.As(err, &maxBytesErr) {
			apiError(w, http.StatusRequestEntityTooLarge, errors.New("request body exceeds 1 MiB limit"))
			return
		}
		apiError(w, http.StatusBadRequest, err)
		return
	}
	discovery := s.loadAcpDiscovery()
	result, err := s.executePersistentRequest(body, discovery.Apps)
	if err != nil {
		apiError(w, http.StatusBadRequest, err)
		return
	}
	response := map[string]any{"schemaVersion": "meshkit-execution-response/v1"}
	for key, value := range result {
		response[key] = value
	}
	writeJSON(w, http.StatusCreated, response)
}

func (s *AppServer) handleSettlements(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
		return
	}
	discovery := s.loadAcpDiscovery()
	state, err := s.readPersistentSuperappState(discovery.Apps)
	if err != nil {
		apiError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"schemaVersion":    "meshkit-settlement-query-response/v1",
		"settlementLedger": state["settlementLedger"],
	})
}

func (s *AppServer) handleTrustPaths(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"error": "method_not_allowed"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"provider":    "maroo",
		"network":     "maroo-testnet",
		"indexerMode": "go-stub-empty-scan",
		"scanStatus":  "ready",
		"records":     []any{},
	})
}

func parseAgentChatMessages(input map[string]any) ([]AgentChatMessage, error) {
	if rawMessage := strings.TrimSpace(firstString(input, "message")); rawMessage != "" {
		return []AgentChatMessage{{Role: "user", Content: rawMessage}}, nil
	}
	rawMessages, ok := input["messages"].([]any)
	if !ok || len(rawMessages) == 0 {
		return nil, errors.New("messages must include at least one user message")
	}
	messages := []AgentChatMessage{}
	for _, raw := range rawMessages {
		item, ok := raw.(map[string]any)
		if !ok {
			return nil, errors.New("messages must be JSON objects")
		}
		role := strings.TrimSpace(firstString(item, "role"))
		content := strings.TrimSpace(firstString(item, "content"))
		if role != "user" && role != "assistant" {
			return nil, errors.New("messages may only include user and assistant roles")
		}
		if content == "" {
			return nil, errors.New("message content is required")
		}
		messages = append(messages, AgentChatMessage{Role: role, Content: content})
	}
	return messages, nil
}

func (s *AppServer) openAIChatCompletion(apiKey string, messages []AgentChatMessage, tools []map[string]any) (AgentChatMessage, error) {
	baseURL := strings.TrimRight(envOr("OPENAI_BASE_URL", "https://api.openai.com/v1"), "/")
	model := envOr("OPENAI_MODEL", "gpt-5.4-mini")
	body := map[string]any{
		"model":       model,
		"temperature": 0,
		"messages":    messages,
		"tools":       tools,
		"tool_choice": "auto",
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return AgentChatMessage{}, err
	}
	req, err := http.NewRequest(http.MethodPost, baseURL+"/chat/completions", bytes.NewReader(encoded))
	if err != nil {
		return AgentChatMessage{}, err
	}
	req.Header.Set("authorization", "Bearer "+apiKey)
	req.Header.Set("content-type", "application/json")
	client := s.httpClient
	if client == nil {
		client = http.DefaultClient
	}
	response, err := client.Do(req)
	if err != nil {
		return AgentChatMessage{}, err
	}
	defer response.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(response.Body, requestBodyLimitBytes))
	if err != nil {
		return AgentChatMessage{}, err
	}
	var parsed OpenAIChatResponse
	if err := json.Unmarshal(payload, &parsed); err != nil {
		return AgentChatMessage{}, fmt.Errorf("OpenAI chat/completions returned invalid JSON: %w", err)
	}
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		if parsed.Error != nil {
			return AgentChatMessage{}, fmt.Errorf("OpenAI chat/completions returned HTTP %d: %v", response.StatusCode, parsed.Error["message"])
		}
		return AgentChatMessage{}, fmt.Errorf("OpenAI chat/completions returned HTTP %d", response.StatusCode)
	}
	if len(parsed.Choices) == 0 {
		return AgentChatMessage{}, errors.New("OpenAI chat/completions returned no choices")
	}
	message := parsed.Choices[0].Message
	if message.Role == "" {
		message.Role = "assistant"
	}
	return message, nil
}

func (s *AppServer) executeAgentToolCall(call OpenAIToolCall, apps []AppDescriptor) (map[string]any, error) {
	args := map[string]any{}
	if strings.TrimSpace(call.Function.Arguments) != "" {
		if err := json.Unmarshal([]byte(call.Function.Arguments), &args); err != nil {
			return nil, fmt.Errorf("tool arguments must be valid JSON for %s", call.Function.Name)
		}
	}
	switch call.Function.Name {
	case "remember_preference":
		result, err := s.upsertPreference(map[string]any{
			"userId":  defaultUserID,
			"agentId": defaultAgentID,
			"key":     firstString(args, "key"),
			"value":   firstString(args, "value"),
			"source":  "agent-chat",
		}, apps)
		if err != nil {
			return nil, err
		}
		preference, _ := result["preference"].(MemoryEntry)
		droppedReason := droppedPreferenceReason(result["droppedPreference"])
		remembered := result["preference"] != nil || droppedReason == "duplicate-content"
		return map[string]any{
			"kind":          "preference",
			"key":           firstString(args, "key"),
			"saved":         result["preference"] != nil,
			"remembered":    remembered,
			"preferenceId":  preference.MemoryID,
			"droppedReason": droppedReason,
		}, nil
	case "get_settlement_ledger":
		state, err := s.readPersistentSuperappState(apps)
		if err != nil {
			return nil, err
		}
		return map[string]any{"kind": "settlement_ledger", "settlementLedger": state["settlementLedger"]}, nil
	default:
		capabilityID := capabilityIDFromToolName(call.Function.Name)
		app, capability, ok := findCapability(apps, capabilityID)
		if !ok {
			return nil, fmt.Errorf("LLM called non-discovered tool: %s", call.Function.Name)
		}
		amount := numberValue(args["amount"], 0)
		if capability.RequiresPayment && amount == 0 {
			amount = 42
		}
		result, err := s.executePersistentRequest(map[string]any{
			"capabilityId": capability.ID,
			"amount":       amount,
			"requestId":    fmt.Sprintf("req-chat-%s-%d", strings.ReplaceAll(capability.ID, ".", "-"), time.Now().UnixNano()),
			"userId":       defaultUserID,
			"agentId":      defaultAgentID,
		}, apps)
		if err != nil {
			return nil, err
		}
		record := result["transactionRecord"].(TransactionRecord)
		return map[string]any{
			"kind":         "acp_invocation",
			"appId":        app.AppID,
			"displayName":  app.DisplayName,
			"capabilityId": capability.ID,
			"urlScheme":    capability.URLScheme,
			"userSummary":  firstString(args, "userSummary"),
			"noteText":     firstString(args, "noteText"),
			"items":        args["items"],
			"budgetOkrw":   numberValue(args["budgetOkrw"], amount),
			"route":        record.Route,
			"status":       record.Status,
			"requestId":    record.RequestID,
			"txHash":       record.TxHash,
			"recordType":   record.RecordType,
		}, nil
	}
}

func agentSupportTools() []map[string]any {
	return []map[string]any{
		{
			"type": "function",
			"function": map[string]any{
				"name":        "remember_preference",
				"description": "Save one durable user preference. Call separately for distinct preferences.",
				"parameters": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"properties": map[string]any{
						"key":   map[string]any{"type": "string"},
						"value": map[string]any{"type": "string"},
					},
					"required": []string{"key", "value"},
				},
			},
		},
		{
			"type": "function",
			"function": map[string]any{
				"name":        "get_settlement_ledger",
				"description": "Read the current on-chain-only settlement ledger after paid app calls.",
				"parameters": map[string]any{
					"type":                 "object",
					"additionalProperties": false,
					"properties":           map[string]any{},
				},
			},
		},
	}
}

func agentCapabilityTools(apps []AppDescriptor) []map[string]any {
	tools := []map[string]any{}
	for _, app := range apps {
		for _, capability := range app.Capabilities {
			properties := map[string]any{
				"amount":      map[string]any{"type": "number", "description": "Payment amount, or 0 for non-payment capabilities."},
				"userSummary": map[string]any{"type": "string", "description": "Short user-facing reason for this invocation."},
			}
			required := []string{"amount", "userSummary"}
			if capability.ID == "notes.append_note" {
				properties["noteText"] = map[string]any{"type": "string", "description": "Exact note text to append."}
				properties["noteRef"] = map[string]any{"type": "string", "description": "Stable local note reference."}
				required = append(required, "noteText")
			}
			if capability.ID == "grocery.purchase_essentials" {
				properties["items"] = map[string]any{"type": "array", "items": map[string]any{"type": "string"}}
				properties["budgetOkrw"] = map[string]any{"type": "number"}
				required = append(required, "items", "budgetOkrw")
			}
			tools = append(tools, map[string]any{
				"type": "function",
				"function": map[string]any{
					"name": strings.ReplaceAll("invoke__"+capability.ID, ".", "__"),
					"description": strings.Join([]string{
						fmt.Sprintf("Invoke discovered ACP capability %s on %s.", capability.ID, app.DisplayName),
						fmt.Sprintf("appId=%s; acpEndpoint=%s; transport=%s; urlScheme=%s; routingHint=%s.", app.AppID, app.AcpEndpoint, app.MCPTransport, capability.URLScheme, capability.RoutingHint),
					}, " "),
					"parameters": map[string]any{
						"type":                 "object",
						"additionalProperties": false,
						"properties":           properties,
						"required":             required,
					},
				},
			})
		}
	}
	return tools
}

func discoverySummaryForAgent(apps []AppDescriptor) []map[string]any {
	summary := []map[string]any{}
	for _, app := range apps {
		capabilities := []map[string]any{}
		for _, capability := range app.Capabilities {
			capabilities = append(capabilities, map[string]any{
				"id":              capability.ID,
				"requiresPayment": capability.RequiresPayment,
				"asset":           capability.Asset,
				"urlScheme":       capability.URLScheme,
				"routingHint":     capability.RoutingHint,
				"inputSchema":     capability.InputSchema,
			})
		}
		summary = append(summary, map[string]any{
			"appId":          app.AppID,
			"displayName":    app.DisplayName,
			"acpEndpoint":    app.AcpEndpoint,
			"mcpTransport":   app.MCPTransport,
			"capabilities":   capabilities,
			"registrySource": app.RegistrySource,
		})
	}
	return summary
}

func mustJSON(value any) string {
	encoded, err := json.Marshal(value)
	if err != nil {
		return "{}"
	}
	return string(encoded)
}

func capabilityIDFromToolName(name string) string {
	return strings.ReplaceAll(strings.TrimPrefix(name, "invoke__"), "__", ".")
}

func findCapability(apps []AppDescriptor, capabilityID string) (AppDescriptor, Capability, bool) {
	for _, app := range apps {
		for _, capability := range app.Capabilities {
			if capability.ID == capabilityID {
				return app, capability, true
			}
		}
	}
	return AppDescriptor{}, Capability{}, false
}

func droppedPreferenceReason(raw any) string {
	dropped, ok := raw.(map[string]any)
	if !ok {
		return ""
	}
	return fmt.Sprint(dropped["reason"])
}

func (s *AppServer) handleStatic(w http.ResponseWriter, r *http.Request) {
	path := r.URL.Path
	if path == "/" {
		path = "/index.html"
	}
	clean := filepath.Clean(strings.TrimPrefix(path, "/"))
	filePath := filepath.Join(s.staticDir, clean)
	rel, err := filepath.Rel(s.staticDir, filePath)
	if err != nil || strings.HasPrefix(rel, "..") {
		http.Error(w, "Forbidden", http.StatusForbidden)
		return
	}
	http.ServeFile(w, r, filePath)
}

type Discovery struct {
	RegistryMode  string
	RegistryDir   string
	RegistryFiles []string
	RegistryTrust map[string]any
	RegistryError any
	Apps          []AppDescriptor
}

func fallbackApps() []AppDescriptor {
	return []AppDescriptor{
		{
			SchemaVersion: acpSchemaVersion,
			AppID:         "app.hermes-chat", OcgAppID: "app.hermes-chat",
			DisplayName: "HermesChat", Publisher: "MeshKit Samples",
			AcpEndpoint: "acp://hermes-chat/apps", MCPTransport: "app-to-app-url-scheme",
			BundleID: "ai.meshkit.sample.hermeschat", Platform: "local", RegistrySource: "local-fixture",
			Capabilities: []Capability{{
				ID: "agent.plan_trip", DisplayName: "Plan errand", Risk: "read_only", Consent: "remember_for_app",
				RequiresPayment: false, Asset: nil, URLScheme: "hermeschat://mesh/invoke",
				InputSchema: []string{"intent", "preference_refs"}, ResultSchema: []string{"plan", "recommended_app_ids"},
				RoutingHint: "offchain_app_call",
			}},
		},
		{
			SchemaVersion: acpSchemaVersion,
			AppID:         "app.mint-notes", OcgAppID: "ai.meshkit.sample.notes",
			DisplayName: "MintNotes", Publisher: "MeshKit Samples",
			AcpEndpoint: "acp://mint-notes/apps", MCPTransport: "app-to-app-url-scheme",
			BundleID: "ai.meshkit.sample.mintnotes", Platform: "ios-demo", RegistrySource: "meshkit-ios-sample",
			Capabilities: []Capability{{
				ID: "notes.append_note", DisplayName: "Append note", Risk: "write:user_content", Consent: "per_invocation",
				RequiresPayment: false, Asset: nil, URLScheme: "mintnotes://mesh/invoke",
				InputSchema: []string{"note_ref", "text"}, ResultSchema: []string{"status", "note_ref", "audit_id"},
				RoutingHint: "offchain_app_call",
			}},
		},
		{
			SchemaVersion: acpSchemaVersion,
			AppID:         "app.dailymart", OcgAppID: "ai.meshkit.sample.dailymart",
			DisplayName: "DailyMart", Publisher: "MeshKit Samples",
			AcpEndpoint: "acp://dailymart/apps", MCPTransport: "app-to-app-url-scheme",
			BundleID: "ai.meshkit.sample.dailymart", Platform: "ios-demo", RegistrySource: "meshkit-ios-sample",
			Capabilities: []Capability{{
				ID: "grocery.purchase_essentials", DisplayName: "Purchase essentials", Risk: "spend:money", Consent: "budgeted_per_invocation",
				RequiresPayment: true, Asset: "OKRW", URLScheme: "dailymart://mesh/invoke",
				InputSchema: []string{"items", "address_ref", "budget_okrw"}, ResultSchema: []string{"status", "order_id", "total_okrw", "receipt_id"},
				RoutingHint: "onchain_payment",
			}},
		},
	}
}

func samplePreferenceEvents() []PreferenceEvent {
	return []PreferenceEvent{
		{ID: "pref-payment-1", Key: "payment_proof_policy", UserID: defaultUserID, AgentID: defaultAgentID, Role: "user", Kind: "conversation", Content: "agent payments use on-chain OKRW proof and non-payment calls stay off-chain", Value: "agent payments use on-chain OKRW proof and non-payment calls stay off-chain", Source: "seed-fixture", Signals: map[string]any{"userPreference": 1, "decision": 1}, CreatedAt: "2026-06-08T09:00:00.000Z", UpdatedAt: "2026-06-08T09:00:00.000Z", LastAccessedAt: "2026-06-08T09:00:00.000Z", AccessCount: 1},
		{ID: "pref-privacy-1", Key: "privacy_policy", UserID: defaultUserID, AgentID: defaultAgentID, Role: "user", Kind: "conversation", Content: "cart/address/user/consent details stay off-chain", Value: "cart/address/user/consent details stay off-chain", Source: "seed-fixture", Signals: map[string]any{"userPreference": 1, "privacy": 1}, CreatedAt: "2026-06-08T09:03:00.000Z", UpdatedAt: "2026-06-08T09:03:00.000Z", LastAccessedAt: "2026-06-08T09:03:00.000Z", AccessCount: 1},
		{ID: "pref-food-1", Key: "grocery_defaults", UserID: defaultUserID, AgentID: defaultAgentID, Role: "user", Kind: "conversation", Content: "User prefers low-sugar grocery defaults and wants bananas before snacks.", Value: "User prefers low-sugar grocery defaults and wants bananas before snacks.", Source: "demo-fixture", Signals: map[string]any{"userPreference": 1, "projectRelevance": 0.8}, CreatedAt: "2026-06-08T09:05:00.000Z", UpdatedAt: "2026-06-08T09:05:00.000Z", LastAccessedAt: "2026-06-08T09:05:00.000Z", AccessCount: 1},
	}
}

func (s *AppServer) loadAcpDiscovery() Discovery {
	fallback := fallbackApps()
	signedDir := filepath.Join(s.registryDir, "signed")
	jwksPath := filepath.Join(s.registryDir, "jwks", "test-registry-jwks.json")
	records, err := readSignedManifests(signedDir, jwksPath)
	if err == nil {
		apps, appErr := appsFromManifestRecords(records, "signed-ocg-registry")
		if appErr != nil {
			return signedRegistryError(signedDir, records, fallback, appErr)
		}
		apps = mergeFallback(apps, fallback)
		return Discovery{RegistryMode: "signed-ocg-registry", RegistryDir: signedDir, RegistryFiles: manifestFiles(records), RegistryTrust: registryTrust(records, "signed-ocg-registry", ""), Apps: apps}
	}
	if hasManifestFiles(signedDir) {
		return signedRegistryError(signedDir, nil, fallback, err)
	}
	unsigned, unsignedErr := readManifests(s.registryDir)
	if unsignedErr == nil {
		apps, appErr := appsFromManifestRecords(unsigned, "ocg-registry")
		if appErr != nil {
			return Discovery{RegistryMode: "fallback-fixture", RegistryDir: s.registryDir, RegistryFiles: manifestFiles(unsigned), RegistryTrust: registryTrust(nil, "fallback-fixture", appErr.Error()), RegistryError: appErr.Error(), Apps: fallback}
		}
		apps = mergeFallback(apps, fallback)
		return Discovery{RegistryMode: "ocg-registry", RegistryDir: s.registryDir, RegistryFiles: manifestFiles(unsigned), RegistryTrust: registryTrust(unsigned, "ocg-registry", err.Error()), Apps: apps}
	}
	return Discovery{RegistryMode: "fallback-fixture", RegistryDir: s.registryDir, RegistryFiles: []string{}, RegistryTrust: registryTrust(nil, "fallback-fixture", err.Error()), RegistryError: unsignedErr.Error(), Apps: fallback}
}

func signedRegistryError(signedDir string, records []ManifestRecord, fallback []AppDescriptor, err error) Discovery {
	files := manifestFiles(records)
	if len(files) == 0 {
		files = manifestFileNames(signedDir)
	}
	return Discovery{
		RegistryMode:  "signed-ocg-registry-error",
		RegistryDir:   signedDir,
		RegistryFiles: files,
		RegistryTrust: registryTrust(records, "signed-ocg-registry-error", err.Error()),
		RegistryError: err.Error(),
		Apps:          fallback,
	}
}

type ManifestRecord struct {
	FileName              string
	Manifest              map[string]any
	SignatureVerification map[string]any
}

func readManifests(dir string) ([]ManifestRecord, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, err
	}
	var files []string
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".ocg.json") {
			files = append(files, entry.Name())
		}
	}
	sort.Strings(files)
	var records []ManifestRecord
	for _, file := range files {
		raw, err := os.ReadFile(filepath.Join(dir, file))
		if err != nil {
			return nil, err
		}
		var manifest map[string]any
		if err := json.Unmarshal(raw, &manifest); err != nil {
			return nil, err
		}
		records = append(records, ManifestRecord{FileName: file, Manifest: manifest})
	}
	return records, nil
}

func readSignedManifests(dir, jwksPath string) ([]ManifestRecord, error) {
	raw, err := os.ReadFile(jwksPath)
	if err != nil {
		return nil, err
	}
	var jwks map[string]any
	if err := json.Unmarshal(raw, &jwks); err != nil {
		return nil, err
	}
	records, err := readManifests(dir)
	if err != nil {
		return nil, err
	}
	if len(records) == 0 {
		return nil, errors.New("signed OCG registry must include at least one manifest")
	}
	for idx := range records {
		verification, err := verifyRegistrySignature(records[idx].Manifest, jwks)
		if err != nil {
			return nil, err
		}
		records[idx].SignatureVerification = verification
	}
	return records, nil
}

func manifestFileNames(dir string) []string {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return []string{}
	}
	files := []string{}
	for _, entry := range entries {
		if !entry.IsDir() && strings.HasSuffix(entry.Name(), ".ocg.json") {
			files = append(files, entry.Name())
		}
	}
	sort.Strings(files)
	return files
}

func hasManifestFiles(dir string) bool {
	return len(manifestFileNames(dir)) > 0
}

func verifyRegistrySignature(manifest map[string]any, jwks map[string]any) (map[string]any, error) {
	rawSig, ok := manifest["registry_signature"].(map[string]any)
	if !ok {
		return nil, errors.New("registry_signature is required")
	}
	alg, _ := rawSig["alg"].(string)
	kid, _ := rawSig["kid"].(string)
	canonicalization, _ := rawSig["canonicalization"].(string)
	value, _ := rawSig["value"].(string)
	if alg != "HS256-test-only" {
		return nil, fmt.Errorf("unsupported registry signature alg: %s", alg)
	}
	if canonicalization != "ocg-canonical-json/v1" {
		return nil, fmt.Errorf("unsupported canonicalization: %s", canonicalization)
	}
	key, err := findJwksKey(jwks, kid, alg)
	if err != nil {
		return nil, err
	}
	unsigned := map[string]any{}
	for k, v := range manifest {
		if k != "registry_signature" {
			unsigned[k] = v
		}
	}
	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(canonicalJSON(unsigned)))
	expected := base64.RawURLEncoding.EncodeToString(mac.Sum(nil))
	if !hmac.Equal([]byte(expected), []byte(value)) {
		return nil, fmt.Errorf("registry signature mismatch: %s", kid)
	}
	issuer, _ := jwks["issuer"].(string)
	issuedAt, _ := rawSig["issued_at"].(string)
	return map[string]any{"status": "verified", "alg": alg, "kid": kid, "canonicalization": canonicalization, "issuedAt": issuedAt, "issuer": issuer, "keyStatus": "active"}, nil
}

func findJwksKey(jwks map[string]any, kid, alg string) ([]byte, error) {
	keys, _ := jwks["keys"].([]any)
	for _, raw := range keys {
		key, _ := raw.(map[string]any)
		if key["kid"] == kid && key["alg"] == alg && key["status"] == "active" {
			encoded, _ := key["k"].(string)
			return base64.RawURLEncoding.DecodeString(encoded)
		}
	}
	return nil, fmt.Errorf("registry signing key not found: %s", kid)
}

func canonicalJSON(value any) string {
	switch typed := value.(type) {
	case []any:
		parts := make([]string, len(typed))
		for i, item := range typed {
			parts[i] = canonicalJSON(item)
		}
		return "[" + strings.Join(parts, ",") + "]"
	case map[string]any:
		keys := make([]string, 0, len(typed))
		for key := range typed {
			keys = append(keys, key)
		}
		sort.Strings(keys)
		parts := make([]string, 0, len(keys))
		for _, key := range keys {
			keyJSON, _ := json.Marshal(key)
			parts = append(parts, string(keyJSON)+":"+canonicalJSON(typed[key]))
		}
		return "{" + strings.Join(parts, ",") + "}"
	default:
		raw, _ := json.Marshal(typed)
		return string(raw)
	}
}

func manifestFiles(records []ManifestRecord) []string {
	files := make([]string, len(records))
	for i, record := range records {
		files[i] = record.FileName
	}
	return files
}

func registryTrust(records []ManifestRecord, mode, signedError string) map[string]any {
	verified := 0
	issuer := ""
	keyIDs := map[string]bool{}
	for _, record := range records {
		if record.SignatureVerification != nil {
			if record.SignatureVerification["status"] == "verified" {
				verified++
			}
			if issuer == "" {
				issuer, _ = record.SignatureVerification["issuer"].(string)
			}
			if kid, ok := record.SignatureVerification["kid"].(string); ok {
				keyIDs[kid] = true
			}
		}
	}
	var keys []string
	for key := range keyIDs {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return map[string]any{"mode": mode, "signed": verified > 0, "verifiedCount": verified, "issuer": issuer, "keyIds": keys, "signedError": signedError}
}

func appsFromManifestRecords(records []ManifestRecord, source string) ([]AppDescriptor, error) {
	apps := make([]AppDescriptor, 0, len(records))
	for _, record := range records {
		app, err := createAcpAppFromManifest(record.Manifest, source, record.SignatureVerification)
		if err != nil {
			return nil, fmt.Errorf("%s: %w", record.FileName, err)
		}
		apps = append(apps, app)
	}
	return apps, nil
}

func createAcpAppFromManifest(manifest map[string]any, source string, verification map[string]any) (AppDescriptor, error) {
	app, ok := manifest["app"].(map[string]any)
	if !ok {
		return AppDescriptor{}, errors.New("OCG manifest app is required")
	}
	appID, _ := app["app_id"].(string)
	displayName, _ := app["display_name"].(string)
	if displayName == "" {
		displayName = appID
	}
	slug := slugify(displayName)
	urlSchemeSlug := slug
	localAppID := "app." + slug
	bundleID, _ := app["package_name"].(string)
	switch appID {
	case "ai.meshkit.sample.notes":
		localAppID = "app.mint-notes"
		displayName = "MintNotes"
		bundleID = "ai.meshkit.sample.mintnotes"
		urlSchemeSlug = "mintnotes"
	case "ai.meshkit.sample.dailymart":
		localAppID = "app.dailymart"
		displayName = "DailyMart"
		bundleID = "ai.meshkit.sample.dailymart"
		urlSchemeSlug = "dailymart"
	}
	publisher, _ := app["publisher"].(string)
	platform, _ := app["platform"].(string)
	packageName, _ := app["package_name"].(string)
	verified, _ := app["verified"].(bool)
	rawCapabilities, _ := manifest["capabilities"].([]any)
	if len(rawCapabilities) == 0 {
		return AppDescriptor{}, errors.New("OCG manifest capabilities are required")
	}
	capabilities := make([]Capability, 0, len(rawCapabilities))
	for _, rawCapability := range rawCapabilities {
		capabilityMap, _ := rawCapability.(map[string]any)
		id, _ := capabilityMap["id"].(string)
		risk, _ := capabilityMap["risk"].(string)
		consent, _ := capabilityMap["consent"].(string)
		version, _ := capabilityMap["version"].(string)
		description, _ := capabilityMap["description"].(string)
		requiresPayment := risk == "spend:money"
		asset := any(nil)
		if requiresPayment {
			asset = "OKRW"
		}
		capabilities = append(capabilities, Capability{
			ID: id, DisplayName: titleCase(id), Version: version, Description: description, Risk: risk, Consent: consent,
			RequiresPayment: requiresPayment, Asset: asset, URLScheme: urlSchemeSlug + "://mesh/invoke",
			InputSchema: schemaKeys(capabilityMap["input_schema"]), ResultSchema: schemaKeys(capabilityMap["result_schema"]),
			RoutingHint: ternary(requiresPayment, "onchain_payment", "offchain_app_call"),
			OCG:         map[string]any{"inputSchema": capabilityMap["input_schema"], "resultSchema": capabilityMap["result_schema"], "android": capabilityMap["android"]},
		})
	}
	return AppDescriptor{
		SchemaVersion: acpSchemaVersion, AppID: localAppID, OcgAppID: appID, DisplayName: displayName, Publisher: publisher,
		AcpEndpoint: "acp://" + slug + "/apps", MCPTransport: "app-to-app-url-scheme", BundleID: bundleID, Platform: platform,
		PackageName: packageName, Verified: verified, RegistrySource: source, Trust: manifest["trust"], RegistrySignature: manifest["registry_signature"],
		RegistrySignatureVerification: verification, Capabilities: capabilities,
	}, nil
}

func mergeFallback(registryApps, fallback []AppDescriptor) []AppDescriptor {
	byID := map[string]AppDescriptor{}
	for _, app := range registryApps {
		byID[app.AppID] = app
	}
	merged := make([]AppDescriptor, 0, len(fallback)+len(registryApps))
	seen := map[string]bool{}
	for _, app := range fallback {
		if replacement, ok := byID[app.AppID]; ok {
			merged = append(merged, replacement)
		} else {
			merged = append(merged, app)
		}
		seen[app.AppID] = true
	}
	for _, app := range registryApps {
		if !seen[app.AppID] {
			merged = append(merged, app)
		}
	}
	return merged
}

func schemaKeys(raw any) []string {
	schema, _ := raw.(map[string]any)
	required, _ := schema["required"].([]any)
	if len(required) > 0 {
		keys := make([]string, 0, len(required))
		for _, key := range required {
			keys = append(keys, fmt.Sprint(key))
		}
		return keys
	}
	properties, _ := schema["properties"].(map[string]any)
	keys := make([]string, 0, len(properties))
	for key := range properties {
		keys = append(keys, key)
	}
	sort.Strings(keys)
	return keys
}

func slugify(value string) string {
	lower := strings.ToLower(value)
	var builder strings.Builder
	lastDash := false
	for _, r := range lower {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			builder.WriteRune(r)
			lastDash = false
		} else if !lastDash {
			builder.WriteRune('-')
			lastDash = true
		}
	}
	return strings.Trim(builder.String(), "-")
}

func titleCase(id string) string {
	parts := regexp.MustCompile(`[._-]+`).Split(id, -1)
	for i, part := range parts {
		if part != "" {
			parts[i] = strings.ToUpper(part[:1]) + part[1:]
		}
	}
	return strings.Join(parts, " ")
}

func ternary(condition bool, yes, no string) string {
	if condition {
		return yes
	}
	return no
}

func (s *AppServer) storePath() string {
	return filepath.Join(s.dataDir, "superapp-store.json")
}

func (s *AppServer) loadStore() (StoreState, error) {
	raw, err := os.ReadFile(s.storePath())
	if err == nil {
		var store StoreState
		if err := json.Unmarshal(raw, &store); err != nil {
			return StoreState{}, err
		}
		if store.SchemaVersion == "" {
			store.SchemaVersion = storeSchemaVersion
		}
		store = normalizeStoreState(store)
		return store, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return StoreState{}, err
	}
	store := normalizeStoreState(StoreState{SchemaVersion: storeSchemaVersion, PreferenceEvents: samplePreferenceEvents(), ExecutionRecords: []TransactionRecord{}})
	if err := s.saveStore(store); err != nil {
		return StoreState{}, err
	}
	return store, nil
}

func (s *AppServer) saveStore(store StoreState) error {
	store = normalizeStoreState(store)
	if err := os.MkdirAll(s.dataDir, 0o700); err != nil {
		return err
	}
	_ = os.Chmod(s.dataDir, 0o700)
	raw, err := json.MarshalIndent(store, "", "  ")
	if err != nil {
		return err
	}
	tmp := fmt.Sprintf("%s.%d.%d.tmp", s.storePath(), os.Getpid(), time.Now().UnixNano())
	if err := os.WriteFile(tmp, raw, 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, s.storePath()); err != nil {
		return err
	}
	return os.Chmod(s.storePath(), 0o600)
}

func normalizeStoreState(store StoreState) StoreState {
	if store.SchemaVersion == "" {
		store.SchemaVersion = storeSchemaVersion
	}
	for idx, event := range store.PreferenceEvents {
		store.PreferenceEvents[idx] = normalizeStoredPreferenceEvent(event, idx)
	}
	if store.ExecutionRecords == nil {
		store.ExecutionRecords = []TransactionRecord{}
	}
	return store
}

func normalizeStoredPreferenceEvent(event PreferenceEvent, index int) PreferenceEvent {
	if strings.TrimSpace(event.Key) == "" {
		event.Key = fmt.Sprintf("preference_%d", index+1)
	}
	if strings.TrimSpace(event.Content) == "" {
		event.Content = event.Value
	}
	if strings.TrimSpace(event.Value) == "" {
		event.Value = event.Content
	}
	if strings.TrimSpace(event.ID) == "" {
		event.ID = event.Key
	}
	event.UserID = defaultString(event.UserID, defaultUserID)
	event.AgentID = defaultString(event.AgentID, defaultAgentID)
	event.Role = defaultString(event.Role, "user")
	event.Kind = defaultString(event.Kind, "preference")
	event.Source = defaultString(event.Source, "local-api")
	if len(event.Signals) == 0 {
		event.Signals = map[string]any{"userPreference": 1}
	}
	event.CreatedAt = defaultString(event.CreatedAt, nowISO)
	event.UpdatedAt = defaultString(event.UpdatedAt, event.CreatedAt)
	event.LastAccessedAt = defaultString(event.LastAccessedAt, event.UpdatedAt)
	if event.AccessCount <= 0 {
		event.AccessCount = 1
	}
	event.Content = strings.TrimSpace(event.Content)
	event.Value = strings.TrimSpace(event.Value)
	return event
}

func normalizePreferenceEvent(input map[string]any, index int) (PreferenceEvent, error) {
	key := firstString(input, "key", "memoryId", "id")
	if key == "" {
		key = fmt.Sprintf("preference_%d", index+1)
	}
	content := firstString(input, "value", "content")
	if strings.TrimSpace(content) == "" {
		return PreferenceEvent{}, errors.New("preference value is required")
	}
	createdAt := firstString(input, "createdAt")
	if createdAt == "" {
		createdAt = nowISO
	}
	updatedAt := firstString(input, "updatedAt")
	if updatedAt == "" {
		updatedAt = createdAt
	}
	lastAccessedAt := firstString(input, "lastAccessedAt")
	if lastAccessedAt == "" {
		lastAccessedAt = updatedAt
	}
	id := firstString(input, "id")
	if id == "" {
		id = key
	}
	signals, _ := input["signals"].(map[string]any)
	if len(signals) == 0 {
		signals = map[string]any{"userPreference": 1}
	}
	return PreferenceEvent{
		ID: id, Key: key, UserID: defaultString(firstString(input, "userId", "user_id"), defaultUserID), AgentID: defaultString(firstString(input, "agentId", "agent_id"), defaultAgentID),
		Role: defaultString(firstString(input, "role"), "user"), Kind: defaultString(firstString(input, "kind"), "preference"),
		Content: strings.TrimSpace(content), Value: strings.TrimSpace(content), Source: defaultString(firstString(input, "source"), "local-api"),
		Signals: signals, CreatedAt: createdAt, UpdatedAt: updatedAt, LastAccessedAt: lastAccessedAt, AccessCount: 1,
	}, nil
}

func firstString(input map[string]any, keys ...string) string {
	for _, key := range keys {
		if value, ok := input[key]; ok {
			text := strings.TrimSpace(fmt.Sprint(value))
			if text != "" && text != "<nil>" {
				return text
			}
		}
	}
	return ""
}

func defaultString(value, fallback string) string {
	if strings.TrimSpace(value) == "" {
		return fallback
	}
	return value
}

func createPreferenceMemory(events []PreferenceEvent) PreferenceMemory {
	filtered := []PreferenceEvent{}
	dropped := []map[string]any{}
	seen := map[string]bool{}
	strippedByID := map[string]bool{}
	for idx, event := range events {
		event = normalizeStoredPreferenceEvent(event, idx)
		originalContent := event.Content
		content := stripRecalledMemoryContext(event.Content)
		strippedByID[event.ID] = content != originalContent
		event.Content = content
		event.Value = content
		if content == "" {
			dropped = append(dropped, droppedEvent(event, "empty-after-sanitization"))
			continue
		}
		if event.Role == "system" || event.Role == "developer" || event.Role == "internal" || event.Kind == "internal" {
			dropped = append(dropped, droppedEvent(event, "internal-event"))
			continue
		}
		if isInternalReflectionPrompt(content) {
			dropped = append(dropped, droppedEvent(event, "internal-reflection-prompt"))
			continue
		}
		if event.Role == "assistant" && !hasDurableSignal(event.Signals) {
			dropped = append(dropped, droppedEvent(event, "assistant-echo-without-durable-signal"))
			continue
		}
		fingerprint := event.UserID + ":" + event.AgentID + ":" + normalizeQuery(event.Content)
		if seen[fingerprint] {
			dropped = append(dropped, droppedEvent(event, "duplicate-content"))
			continue
		}
		seen[fingerprint] = true
		filtered = append(filtered, event)
	}
	working := make([]MemoryEntry, 0, len(filtered))
	promoted := []MemoryEntry{}
	filteredEvents := []map[string]any{}
	for _, event := range filtered {
		recalledContextStripped := strippedByID[event.ID]
		importance := durableScore(event)
		shouldPromote := importance >= 0.75 || hasDurableSignal(event.Signals) || looksLikeDurableFact(event.Content)
		signals := cloneMap(event.Signals)
		signals["hippocampalDurability"] = ternaryFloat(looksLikeDurableFact(event.Content) || hasDurableSignal(event.Signals), 1, 0.1)
		signals["hippocampalImportance"] = importance
		entry := MemoryEntry{
			SchemaVersion: memorySchemaVersion, MemoryID: event.ID, Key: event.Key, UserID: event.UserID, AgentID: event.AgentID,
			MemoryKind: "young-working-memory", Value: event.Value, Content: event.Content, Source: event.Source,
			CreatedAt: event.CreatedAt, UpdatedAt: event.UpdatedAt, LastAccessedAt: event.LastAccessedAt, AccessCount: event.AccessCount,
			Importance: importance, Signals: signals, Metadata: map[string]any{"role": event.Role, "source": event.Source, "hippocampus": map[string]any{"filtered": true, "recalledContextStripped": recalledContextStripped, "source": "brain-hippocampus-inspired", "promoted": shouldPromote}},
		}
		working = append(working, entry)
		if shouldPromote {
			entry.MemoryKind = "old-long-term-memory"
			entry.PromotedAt = nowISO
			entry.PromotionReason = "hippocampus-filtered-durable-event"
			entry.Metadata["hippocampus"].(map[string]any)["promotionReason"] = "hippocampus-filtered-durable-event"
			promoted = append(promoted, entry)
		}
		filteredEvents = append(filteredEvents, map[string]any{"id": event.ID, "key": event.Key, "role": event.Role, "kind": event.Kind, "source": event.Source, "recalledContextStripped": recalledContextStripped})
	}
	userID, agentID := defaultUserID, defaultAgentID
	if len(filtered) > 0 {
		userID, agentID = filtered[0].UserID, filtered[0].AgentID
	}
	return PreferenceMemory{
		SchemaVersion: memorySchemaVersion, UserID: userID, AgentID: agentID, WorkingMemory: working, PromotedMemory: promoted,
		FilteredEvents: filteredEvents, DroppedEvents: dropped,
		Consolidation: map[string]any{"apiKind": "meshkit_preference_consolidation_result", "schemaVersion": memorySchemaVersion, "filteredCount": len(filtered), "promotedCount": len(promoted), "droppedCount": len(dropped), "policy": "strip recalled memory context, drop internal events, drop assistant echoes without durable signals, dedupe content"},
	}
}

func stripRecalledMemoryContext(content string) string {
	re := regexp.MustCompile(`(?is)<memory-context>.*?</memory-context>`)
	return strings.TrimSpace(re.ReplaceAllString(content, ""))
}

func isInternalReflectionPrompt(content string) bool {
	return regexp.MustCompile(`(?i)^Review the conversation above and consider whether a skill should be saved or updated\.?|Only act when something is genuinely worth saving|SURVEY the existing skill landscape`).MatchString(strings.TrimSpace(content))
}

func hasDurableSignal(signals map[string]any) bool {
	for key, value := range signals {
		name := strings.ToLower(key)
		number, _ := strconv.ParseFloat(fmt.Sprint(value), 64)
		if number > 0 && (strings.Contains(name, "preference") || strings.Contains(name, "correction") || strings.Contains(name, "decision") || strings.Contains(name, "memory") || strings.Contains(name, "durable") || strings.Contains(name, "project") || strings.Contains(name, "recurrence")) {
			return true
		}
	}
	return false
}

func looksLikeDurableFact(content string) bool {
	return regexp.MustCompile(`(?i)\b(user|caller)\s+(prefers|expects|wants|asked|requires|needs)\b|\b(remember|decision|decided|should|must|needs?|requires?|preference|project|memory|hippocampus|consolidation)\b`).MatchString(content)
}

func durableScore(event PreferenceEvent) float64 {
	total := 0.0
	count := 0.0
	for _, value := range event.Signals {
		if number, err := strconv.ParseFloat(fmt.Sprint(value), 64); err == nil {
			total += number
			count++
		}
	}
	average := 0.0
	if count > 0 {
		average = total / count
	}
	if looksLikeDurableFact(event.Content) {
		average += 0.25
	}
	if event.Role == "user" {
		average += 0.15
	}
	return round4(math.Min(1, math.Max(0.01, average)))
}

func droppedEvent(event PreferenceEvent, reason string) map[string]any {
	return map[string]any{"id": event.ID, "key": event.Key, "role": event.Role, "kind": event.Kind, "reason": reason}
}

func cloneMap(input map[string]any) map[string]any {
	output := map[string]any{}
	for key, value := range input {
		output[key] = value
	}
	return output
}

func ternaryFloat(condition bool, yes, no float64) float64 {
	if condition {
		return yes
	}
	return no
}

func normalizeQuery(value string) string {
	return strings.Join(strings.Fields(strings.ToLower(strings.TrimSpace(value))), " ")
}

func tokenize(value string) []string {
	re := regexp.MustCompile(`[^a-z0-9가-힣_:. -]+`)
	return strings.Fields(re.ReplaceAllString(strings.ToLower(value), " "))
}

func retrievePreferences(memory PreferenceMemory, query string, limit int) []MemoryEntry {
	queryTerms := tokenize(query)
	results := append([]MemoryEntry{}, memory.PromotedMemory...)
	for i := range results {
		contentTerms := map[string]bool{}
		for _, term := range tokenize(results[i].Content) {
			contentTerms[term] = true
		}
		matches := 0
		for _, term := range queryTerms {
			if contentTerms[term] {
				matches++
			}
		}
		boost := 0.0
		if regexp.MustCompile(`(?i)payment|pay|결제|on-chain|onchain|chain|okrw`).MatchString(query + results[i].Content) {
			boost = 0.2
		}
		results[i].RetrievalScore = round4(results[i].Importance + float64(matches)*0.15 + boost)
	}
	sort.SliceStable(results, func(i, j int) bool {
		if results[i].RetrievalScore == results[j].RetrievalScore {
			return results[i].MemoryID < results[j].MemoryID
		}
		return results[i].RetrievalScore > results[j].RetrievalScore
	})
	if len(results) > limit {
		return results[:limit]
	}
	return results
}

func (s *AppServer) readPersistentSuperappState(apps []AppDescriptor) (map[string]any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	store, err := s.loadStore()
	if err != nil {
		return nil, err
	}
	state := createSuperappState(store.PreferenceEvents, store.ExecutionRecords, apps)
	state["storeSchemaVersion"] = store.SchemaVersion
	return state, nil
}

func createSuperappState(events []PreferenceEvent, records []TransactionRecord, apps []AppDescriptor) map[string]any {
	memory := createPreferenceMemory(events)
	offchain, _ := routeExecution(apps, memory, "notes.append_note", 0)
	onchain, _ := routeExecution(apps, memory, "grocery.purchase_essentials", 42)
	outputRecords := records
	if len(outputRecords) == 0 {
		result, _ := executeAppToAppRequest(apps, memory, "grocery.purchase_essentials", 42, "req-dailymart-demo-001", defaultUserID, defaultAgentID, nowISO)
		outputRecords = []TransactionRecord{result.TransactionRecord}
	}
	return map[string]any{"apps": apps, "memory": memory, "routing": []RouteDecision{offchain, onchain}, "executionRecords": outputRecords, "settlementLedger": createSettlementLedger(outputRecords)}
}

func (s *AppServer) upsertPreference(input map[string]any, apps []AppDescriptor) (map[string]any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	store, err := s.loadStore()
	if err != nil {
		return nil, err
	}
	input["updatedAt"] = defaultString(firstString(input, "updatedAt"), s.now())
	input["lastAccessedAt"] = defaultString(firstString(input, "lastAccessedAt"), firstString(input, "updatedAt"))
	normalized, err := normalizePreferenceEvent(input, len(store.PreferenceEvents))
	if err != nil {
		return nil, err
	}
	existingIndex := -1
	for i, event := range store.PreferenceEvents {
		if event.UserID == normalized.UserID && event.AgentID == normalized.AgentID && event.Key == normalized.Key {
			existingIndex = i
			break
		}
	}
	if existingIndex >= 0 {
		normalized.ID = store.PreferenceEvents[existingIndex].ID
		normalized.CreatedAt = store.PreferenceEvents[existingIndex].CreatedAt
		store.PreferenceEvents[existingIndex] = normalized
	} else {
		store.PreferenceEvents = append(store.PreferenceEvents, normalized)
	}
	if err := s.saveStore(store); err != nil {
		return nil, err
	}
	state := createSuperappState(store.PreferenceEvents, store.ExecutionRecords, apps)
	memory := state["memory"].(PreferenceMemory)
	var preference any
	for _, entry := range append(memory.PromotedMemory, memory.WorkingMemory...) {
		if entry.Key == normalized.Key && entry.UserID == normalized.UserID && entry.AgentID == normalized.AgentID {
			preference = entry
			break
		}
	}
	var dropped any
	if preference == nil {
		for _, event := range memory.DroppedEvents {
			if event["key"] == normalized.Key {
				dropped = event
				break
			}
		}
	}
	return map[string]any{"preference": preference, "droppedPreference": dropped, "state": state}, nil
}

func (s *AppServer) queryPreferences(query string, limit int, apps []AppDescriptor) ([]MemoryEntry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	store, err := s.loadStore()
	if err != nil {
		return nil, err
	}
	memory := createPreferenceMemory(store.PreferenceEvents)
	return retrievePreferences(memory, query, limit), nil
}

type ExecutionResult struct {
	RouteDecision     RouteDecision     `json:"routeDecision"`
	TransactionRecord TransactionRecord `json:"transactionRecord"`
}

func (s *AppServer) executePersistentRequest(input map[string]any, apps []AppDescriptor) (map[string]any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	store, err := s.loadStore()
	if err != nil {
		return nil, err
	}
	state := createSuperappState(store.PreferenceEvents, store.ExecutionRecords, apps)
	memory := state["memory"].(PreferenceMemory)
	capabilityID := firstString(input, "capabilityId")
	amount, err := parseRequiredAmount(input)
	if err != nil {
		return nil, err
	}
	requestID := firstString(input, "requestId")
	userID := defaultString(firstString(input, "userId", "user_id"), defaultUserID)
	agentID := defaultString(firstString(input, "agentId", "agent_id"), defaultAgentID)
	createdAt := defaultString(firstString(input, "createdAt"), s.now())
	result, err := executeAppToAppRequest(apps, memory, capabilityID, amount, requestID, userID, agentID, createdAt)
	if err != nil {
		return nil, err
	}
	store.ExecutionRecords = append(store.ExecutionRecords, result.TransactionRecord)
	if err := s.saveStore(store); err != nil {
		return nil, err
	}
	return map[string]any{"routeDecision": result.RouteDecision, "transactionRecord": result.TransactionRecord, "settlementLedger": createSettlementLedger(store.ExecutionRecords)}, nil
}

func numberValue(value any, fallback float64) float64 {
	switch typed := value.(type) {
	case float64:
		return typed
	case int:
		return float64(typed)
	case string:
		if parsed, err := strconv.ParseFloat(typed, 64); err == nil {
			return parsed
		}
	}
	return fallback
}

func parseRequiredAmount(input map[string]any) (float64, error) {
	value, ok := input["amount"]
	if !ok {
		return 0, errors.New("amount is required")
	}
	switch typed := value.(type) {
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) || typed < 0 {
			return 0, errors.New("amount must be a non-negative number")
		}
		return typed, nil
	case int:
		if typed < 0 {
			return 0, errors.New("amount must be a non-negative number")
		}
		return float64(typed), nil
	case json.Number:
		parsed, err := typed.Float64()
		if err != nil || math.IsNaN(parsed) || math.IsInf(parsed, 0) || parsed < 0 {
			return 0, errors.New("amount must be a non-negative number")
		}
		return parsed, nil
	case string:
		if strings.TrimSpace(typed) == "" {
			return 0, errors.New("amount must be a non-negative number")
		}
		parsed, err := strconv.ParseFloat(typed, 64)
		if err != nil || math.IsNaN(parsed) || math.IsInf(parsed, 0) || parsed < 0 {
			return 0, errors.New("amount must be a non-negative number")
		}
		return parsed, nil
	default:
		return 0, errors.New("amount must be a non-negative number")
	}
}

func routeExecution(apps []AppDescriptor, memory PreferenceMemory, capabilityID string, amount float64) (RouteDecision, error) {
	if strings.TrimSpace(capabilityID) == "" {
		return RouteDecision{}, errors.New("capabilityId is required")
	}
	if math.IsNaN(amount) || math.IsInf(amount, 0) || amount < 0 {
		return RouteDecision{}, errors.New("amount must be a non-negative number")
	}
	var app AppDescriptor
	var capability Capability
	found := false
	for _, candidateApp := range apps {
		for _, candidate := range candidateApp.Capabilities {
			if candidate.ID == capabilityID {
				app, capability, found = candidateApp, candidate, true
				break
			}
		}
		if found {
			break
		}
	}
	if !found {
		return RouteDecision{}, fmt.Errorf("Capability not found: %s", capabilityID)
	}
	if capability.RequiresPayment && amount <= 0 {
		return RouteDecision{}, fmt.Errorf("%s requires amount greater than 0", capability.ID)
	}
	if !capability.RequiresPayment && amount != 0 {
		return RouteDecision{}, fmt.Errorf("%s does not accept payment amount", capability.ID)
	}
	requiresPayment := capability.RequiresPayment
	recalled := retrievePreferences(memory, capability.ID+" "+capability.DisplayName+" payment", 3)
	policy := deriveRoutingPolicy(memory, recalled, requiresPayment)
	route := "offchain"
	transport := app.MCPTransport
	asset := any(nil)
	privacyBoundary := "Capability payload stays in app-to-app MCP and is not anchored as payment."
	if requiresPayment {
		route = "onchain"
		transport = "maroo-testnet-okrw"
		asset = defaultString(fmt.Sprint(capability.Asset), "OKRW")
		privacyBoundary = "Only request hash, policy hash, tx hash, and settlement status are chain-visible."
	}
	return RouteDecision{SchemaVersion: routingSchemaVersion, Route: route, Transport: transport, AppID: app.AppID, CapabilityID: capability.ID, RequiresPayment: requiresPayment, Asset: asset, Amount: amount, PrivacyBoundary: privacyBoundary, RecalledPreference: recalled, AppliedPolicy: policy}, nil
}

func deriveRoutingPolicy(memory PreferenceMemory, recalled []MemoryEntry, requiresPayment bool) RoutingPolicy {
	var source []MemoryEntry
	for _, entry := range memory.PromotedMemory {
		if entry.Key == "payment_proof_policy" || entry.Key == "privacy_policy" {
			source = append(source, entry)
		}
	}
	if len(source) == 0 {
		for _, entry := range recalled {
			if entry.Key == "payment_proof_policy" || entry.Key == "privacy_policy" {
				source = append(source, entry)
			}
		}
	}
	deduped := []MemoryEntry{}
	seen := map[string]bool{}
	for _, entry := range source {
		if seen[entry.MemoryID] {
			continue
		}
		seen[entry.MemoryID] = true
		deduped = append(deduped, entry)
	}
	source = deduped
	ids := []string{}
	paymentContent := ""
	privacyContent := ""
	for _, entry := range source {
		ids = append(ids, entry.MemoryID)
		switch entry.Key {
		case "payment_proof_policy":
			if paymentContent == "" {
				paymentContent = normalizeQuery(entry.Content)
			}
		case "privacy_policy":
			if privacyContent == "" {
				privacyContent = normalizeQuery(entry.Content)
			}
		}
	}
	paymentPrefersOnchain := includesAnyPattern(paymentContent, []string{`on-chain`, `onchain`, `okrw proof`, `chain.*proof`})
	nonPaymentPrefersOffchain := includesAnyPattern(paymentContent, []string{`non-payment.*off-chain`, `non-payment.*offchain`, `calls stay off-chain`})
	privatePayloadOffchain := includesAnyPattern(privacyContent, []string{`off-chain`, `offchain`, `cart/address/user/consent`, `private`})
	paymentProof := "no-payment-proof"
	if requiresPayment {
		if paymentPrefersOnchain {
			paymentProof = "onchain-okrw-proof"
		} else {
			paymentProof = "onchain-required-by-capability"
		}
	}
	nonPaymentTransport := "offchain-app-to-app-mcp-default"
	if nonPaymentPrefersOffchain {
		nonPaymentTransport = "offchain-app-to-app-mcp"
	}
	payloadPrivacy := "minimal-chain-visible-fields-only"
	if privatePayloadOffchain {
		payloadPrivacy = "private-payload-offchain"
	}
	chainVisible := []string{}
	if requiresPayment {
		chainVisible = []string{"signedRequestHash", "policyHash", "txHash", "settlementStatus"}
	}
	reason := "non-payment app-to-app MCP call stays off-chain"
	if requiresPayment {
		reason = "paid capability uses on-chain proof while private payload fields stay off-chain"
	}
	sourceName := "safe-default"
	if len(ids) > 0 {
		sourceName = "preference-memory"
	}
	return RoutingPolicy{PolicyID: "meshkit-superapp-routing-policy/v1", Source: sourceName, SourceMemoryIDs: ids, PaymentProof: paymentProof, NonPaymentTransport: nonPaymentTransport, PayloadPrivacy: payloadPrivacy, ChainVisibleFields: chainVisible, OffchainFields: []string{"capabilityPayload", "cart", "addressRef", "userIdentityRef", "consentText"}, DecisionReason: reason}
}

func includesAnyPattern(value string, patterns []string) bool {
	for _, pattern := range patterns {
		if regexp.MustCompile("(?i)" + pattern).MatchString(value) {
			return true
		}
	}
	return false
}

func executeAppToAppRequest(apps []AppDescriptor, memory PreferenceMemory, capabilityID string, amount float64, requestID, userID, agentID, now string) (ExecutionResult, error) {
	route, err := routeExecution(apps, memory, capabilityID, amount)
	if err != nil {
		return ExecutionResult{}, err
	}
	stableRequestID := requestID
	if stableRequestID == "" {
		stableRequestID = fmt.Sprintf("req-%s-%g", strings.ReplaceAll(route.CapabilityID, ".", "-"), route.Amount)
	}
	base := fmt.Sprintf("%s:%s:%s:%g:%s", stableRequestID, route.AppID, route.CapabilityID, route.Amount, route.Route)
	signedRequestHash := deterministicHex("signed:"+base, 32)
	policyHash := deterministicHex(strings.Join([]string{"policy", userID, agentID, route.CapabilityID, route.AppliedPolicy.PolicyID, route.AppliedPolicy.PaymentProof, route.AppliedPolicy.PayloadPrivacy, strings.Join(route.AppliedPolicy.SourceMemoryIDs, "|")}, ":"), 32)
	if route.Route == "onchain" {
		txHash := deterministicHex("tx:"+base, 32)
		record := TransactionRecord{SchemaVersion: routingSchemaVersion, Route: "onchain", RecordType: "onchain-sim", RequestID: stableRequestID, UserID: userID, AgentID: agentID, AppID: route.AppID, CapabilityID: route.CapabilityID, Provider: "maroo", Network: "maroo-testnet", Asset: "OKRW", Amount: route.Amount, Status: "confirmed", TxHash: txHash, ExplorerURL: "https://explorer-testnet.maroo.io/tx/" + txHash, PolicyHash: policyHash, SignedRequestHash: signedRequestHash, AppliedPolicy: route.AppliedPolicy, PolicySourceMemoryIDs: route.AppliedPolicy.SourceMemoryIDs, ChainVisibleFields: route.AppliedPolicy.ChainVisibleFields, OffchainFields: route.AppliedPolicy.OffchainFields, CreatedAt: now}
		return ExecutionResult{RouteDecision: route, TransactionRecord: record}, nil
	}
	record := TransactionRecord{SchemaVersion: routingSchemaVersion, Route: "offchain", RecordType: "app-to-app-url-scheme", RequestID: stableRequestID, UserID: userID, AgentID: agentID, AppID: route.AppID, CapabilityID: route.CapabilityID, Amount: 0, Status: "submitted", OffchainRecordID: deterministicHex("offchain:"+base, 12), TxHash: "", SignedRequestHash: signedRequestHash, AppliedPolicy: route.AppliedPolicy, PolicySourceMemoryIDs: route.AppliedPolicy.SourceMemoryIDs, ChainVisibleFields: route.AppliedPolicy.ChainVisibleFields, OffchainFields: route.AppliedPolicy.OffchainFields, CreatedAt: now}
	return ExecutionResult{RouteDecision: route, TransactionRecord: record}, nil
}

func deterministicHex(input string, bytesCount int) string {
	hex := ""
	seed := input
	for len(hex) < bytesCount*2 {
		sum := sha256.Sum256([]byte(seed))
		hex += fmt.Sprintf("%x", sum[:])
		seed = hex
	}
	return "0x" + hex[:bytesCount*2]
}

func createSettlementLedger(records []TransactionRecord) SettlementLedger {
	entries := []map[string]any{}
	for _, record := range records {
		if record.Route != "onchain" && record.TxHash == "" {
			continue
		}
		if record.Amount <= 0 || math.IsNaN(record.Amount) || math.IsInf(record.Amount, 0) {
			continue
		}
		entry := map[string]any{
			"schemaVersion": settlementSchemaVersion, "entryId": fmt.Sprintf("settlement-%d", len(entries)+1), "requestId": record.RequestID,
			"appId": record.AppID, "capabilityId": record.CapabilityID, "provider": defaultString(record.Provider, "maroo"),
			"network": defaultString(record.Network, "maroo-testnet"), "asset": defaultString(record.Asset, "OKRW"), "amount": record.Amount,
			"status": defaultString(record.Status, "verified"), "direction": "debit", "category": settlementCategory(record.CapabilityID),
			"counterparty": settlementCounterparty(record.AppID), "txHash": record.TxHash, "explorerUrl": record.ExplorerURL,
			"policyHash": record.PolicyHash, "signedRequestHash": record.SignedRequestHash, "policyId": record.AppliedPolicy.PolicyID,
			"paymentProof": record.AppliedPolicy.PaymentProof, "payloadPrivacy": record.AppliedPolicy.PayloadPrivacy,
			"policySourceMemoryIds": record.PolicySourceMemoryIDs, "displayTx": compactHash(record.TxHash),
		}
		entries = append(entries, entry)
	}
	totalConfirmed := 0.0
	totalDebits := 0.0
	totalCredits := 0.0
	byStatus, byApp, byCategory, byCounterparty := map[string]float64{}, map[string]float64{}, map[string]float64{}, map[string]float64{}
	for _, entry := range entries {
		amount := numberValue(entry["amount"], 0)
		status := fmt.Sprint(entry["status"])
		byStatus[status] = round4(byStatus[status] + amount)
		if status == "trusted" || status == "verified" || status == "confirmed" {
			totalConfirmed += amount
			if entry["direction"] == "credit" {
				totalCredits += amount
			} else {
				totalDebits += amount
			}
			byApp[fmt.Sprint(entry["appId"])] = round4(byApp[fmt.Sprint(entry["appId"])] + amount)
			byCategory[fmt.Sprint(entry["category"])] = round4(byCategory[fmt.Sprint(entry["category"])] + amount)
			byCounterparty[fmt.Sprint(entry["counterparty"])] = round4(byCounterparty[fmt.Sprint(entry["counterparty"])] + amount)
		}
	}
	return SettlementLedger{SchemaVersion: settlementSchemaVersion, GeneratedAt: nowISO, Entries: entries, Summary: map[string]any{"totalEntries": len(entries), "totalConfirmed": round4(totalConfirmed), "totalDebits": round4(totalDebits), "totalCredits": round4(totalCredits), "asset": "OKRW", "byStatus": byStatus, "byApp": byApp, "byCategory": byCategory, "byCounterparty": byCounterparty}}
}

func settlementCategory(capabilityID string) string {
	if capabilityID == "grocery.purchase_essentials" {
		return "groceries"
	}
	if strings.HasPrefix(capabilityID, "notes.") {
		return "notes"
	}
	return "agent-services"
}

func settlementCounterparty(appID string) string {
	switch appID {
	case "app.dailymart":
		return "DailyMart"
	case "app.mint-notes":
		return "MintNotes"
	default:
		return defaultString(appID, "Unknown")
	}
}

func compactHash(value string) string {
	if value == "" {
		return "-"
	}
	if len(value) <= 17 {
		return value
	}
	return value[:8] + "..." + value[len(value)-6:]
}

func round4(value float64) float64 {
	return math.Round(value*10000) / 10000
}
