;; arbitrage-serialize
;; A smart contract for tracking and executing decentralized arbitrage opportunities
;; Provides mechanisms for cross-chain liquidity tracking, trade serialization, and profit optimization.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-STRATEGY-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PARAMETERS (err u102))
(define-constant ERR-INSUFFICIENT-LIQUIDITY (err u103))

;; Core contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; Liquidity and Trading Frequency Constants
(define-constant FREQUENCY-LOW u1)
(define-constant FREQUENCY-MEDIUM u2)
(define-constant FREQUENCY-HIGH u3)

;; Risk Level Constants
(define-constant RISK-LOW u1)
(define-constant RISK-MEDIUM u2)
(define-constant RISK-HIGH u3)

;; Data Structures

;; Arbitrage Strategy Configuration
(define-map arbitrage-strategies
  { strategy-id: uint }
  {
    owner: principal,
    name: (string-ascii 50),
    description: (string-utf8 200),
    source-chain: (string-ascii 20),
    destination-chain: (string-ascii 20),
    frequency: uint,
    risk-level: uint,
    max-allocation: uint,
    active: bool,
    created-at: uint
  }
)

;; Trader Performance Tracking
(define-map trader-profiles
  { trader: principal }
  {
    total-trades: uint,
    total-profit: uint,
    success-rate: uint,
    current-active-strategies: (list 20 uint),
    reputation-score: uint
  }
)

;; Execution Tracking
(define-map trade-executions
  { strategy-id: uint, execution-id: uint }
  {
    trader: principal,
    timestamp: uint,
    profit: uint,
    success: bool,
    details: (string-utf8 500)
  }
)

;; Strategy Performance Metrics
(define-map strategy-performance
  { strategy-id: uint }
  {
    total-executions: uint,
    total-profit: uint,
    success-rate: uint,
    last-executed: uint
  }
)

;; Counters
(define-data-var strategy-id-counter uint u0)
(define-data-var execution-id-counter uint u0)

;; Private Helper Functions

(define-private (increment-strategy-id)
  (let ((next-id (+ (var-get strategy-id-counter) u1)))
    (var-set strategy-id-counter next-id)
    next-id
  )
)

(define-private (increment-execution-id)
  (let ((next-id (+ (var-get execution-id-counter) u1)))
    (var-set execution-id-counter next-id)
    next-id
  )
)

(define-private (is-valid-risk-level (risk-level uint))
  (or
    (is-eq risk-level RISK-LOW)
    (is-eq risk-level RISK-MEDIUM)
    (is-eq risk-level RISK-HIGH)
  )
)

;; Read-Only Functions

(define-read-only (get-strategy (strategy-id uint))
  (map-get? arbitrage-strategies { strategy-id: strategy-id })
)

(define-read-only (get-trader-profile (trader principal))
  (default-to 
    { 
      total-trades: u0, 
      total-profit: u0, 
      success-rate: u0, 
      current-active-strategies: (list), 
      reputation-score: u0 
    }
    (map-get? trader-profiles { trader: trader })
  )
)

;; Public Functions

(define-public (create-arbitrage-strategy
  (name (string-ascii 50))
  (description (string-utf8 200))
  (source-chain (string-ascii 20))
  (destination-chain (string-ascii 20))
  (frequency uint)
  (risk-level uint)
  (max-allocation uint)
)
  (let (
    (new-strategy-id (increment-strategy-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Validate risk level
    (asserts! (is-valid-risk-level risk-level) ERR-INVALID-PARAMETERS)
    
    ;; Create the strategy
    (map-set arbitrage-strategies
      { strategy-id: new-strategy-id }
      {
        owner: tx-sender,
        name: name,
        description: description,
        source-chain: source-chain,
        destination-chain: destination-chain,
        frequency: frequency,
        risk-level: risk-level,
        max-allocation: max-allocation,
        active: true,
        created-at: current-time
      }
    )
    
    ;; Update trader profile
    (let (
      (trader-profile (default-to 
        { 
          total-trades: u0, 
          total-profit: u0, 
          success-rate: u0, 
          current-active-strategies: (list), 
          reputation-score: u0 
        }
        (map-get? trader-profiles { trader: tx-sender })
      ))
      (updated-strategies (unwrap-panic (as-max-len? (append (get current-active-strategies trader-profile) new-strategy-id) u20)))
    )
      (map-set trader-profiles
        { trader: tx-sender }
        {
          total-trades: (get total-trades trader-profile),
          total-profit: (get total-profit trader-profile),
          success-rate: (get success-rate trader-profile),
          current-active-strategies: updated-strategies,
          reputation-score: (get reputation-score trader-profile)
        }
      )
    )
    
    (ok new-strategy-id)
  )
)

(define-public (execute-arbitrage-strategy
  (strategy-id uint)
  (profit uint)
  (details (string-utf8 500))
)
  (let (
    (strategy (unwrap! (map-get? arbitrage-strategies { strategy-id: strategy-id }) ERR-STRATEGY-NOT-FOUND))
    (new-execution-id (increment-execution-id))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Verify strategy ownership
    (asserts! (is-eq tx-sender (get owner strategy)) ERR-NOT-AUTHORIZED)
    
    ;; Verify strategy is active
    (asserts! (get active strategy) ERR-STRATEGY-NOT-FOUND)
    
    ;; Record execution
    (map-set trade-executions
      { strategy-id: strategy-id, execution-id: new-execution-id }
      {
        trader: tx-sender,
        timestamp: current-time,
        profit: profit,
        success: (> profit u0),
        details: details
      }
    )
    
    ;; Update strategy performance
    (let (
      (performance (default-to 
        { total-executions: u0, total-profit: u0, success-rate: u0, last-executed: u0 }
        (map-get? strategy-performance { strategy-id: strategy-id })
      ))
      (new-total-executions (+ (get total-executions performance) u1))
      (new-total-profit (+ (get total-profit performance) profit))
      (success-count (if (> profit u0) u1 u0))
    )
      (map-set strategy-performance
        { strategy-id: strategy-id }
        {
          total-executions: new-total-executions,
          total-profit: new-total-profit,
          success-rate: (/ (* success-count u100) new-total-executions),
          last-executed: current-time
        }
      )
    )
    
    ;; Update trader profile
    (let (
      (trader-profile (default-to 
        { 
          total-trades: u0, 
          total-profit: u0, 
          success-rate: u0, 
          current-active-strategies: (list), 
          reputation-score: u0 
        }
        (map-get? trader-profiles { trader: tx-sender })
      ))
      (success (> profit u0))
      (success-count (if success u1 u0))
    )
      (map-set trader-profiles
        { trader: tx-sender }
        {
          total-trades: (+ (get total-trades trader-profile) u1),
          total-profit: (+ (get total-profit trader-profile) profit),
          success-rate: (/ (* success-count u100) (+ (get total-trades trader-profile) u1)),
          current-active-strategies: (get current-active-strategies trader-profile),
          reputation-score: (+ (get reputation-score trader-profile) (if success u10 u0))
        }
      )
    )
    
    (ok new-execution-id)
  )
)

;; Toggle strategy active status
(define-public (toggle-strategy-active (strategy-id uint))
  (let (
    (strategy (unwrap! (map-get? arbitrage-strategies { strategy-id: strategy-id }) ERR-STRATEGY-NOT-FOUND))
  )
    ;; Verify ownership
    (asserts! (is-eq tx-sender (get owner strategy)) ERR-NOT-AUTHORIZED)
    
    ;; Toggle active status
    (map-set arbitrage-strategies
      { strategy-id: strategy-id }
      {
        owner: (get owner strategy),
        name: (get name strategy),
        description: (get description strategy),
        source-chain: (get source-chain strategy),
        destination-chain: (get destination-chain strategy),
        frequency: (get frequency strategy),
        risk-level: (get risk-level strategy),
        max-allocation: (get max-allocation strategy),
        active: (not (get active strategy)),
        created-at: (get created-at strategy)
      }
    )
    
    (ok (not (get active strategy)))
  )
)