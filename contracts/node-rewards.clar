;; node-rewards
;; 
;; This contract implements a token-based reward system for IoT node operators
;; on the Stacks blockchain. The system incentivizes reliable operation, data quality,
;; and network contribution by distributing rewards based on performance metrics.
;; Node operators earn reputation scores that influence their reward rates, creating
;; economic alignment between operators and the network's health.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NODE-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-CLAIMED (err u102))
(define-constant ERR-NO-REWARDS (err u103))
(define-constant ERR-INVALID-UPTIME (err u104))
(define-constant ERR-INVALID-QUALITY (err u105))
(define-constant ERR-INVALID-CONTRIBUTION (err u106))
(define-constant ERR-COOLDOWN-ACTIVE (err u107))
(define-constant ERR-NODE-ALREADY-REGISTERED (err u108))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant REWARD-PRECISION u10000) ;; Precision factor for reward calculations
(define-constant MIN-CLAIM-COOLDOWN u144) ;; Minimum blocks between claims (approximately 24 hours)
(define-constant BASE-REWARD-RATE u100) ;; Base reward rate per block in tokens (scaled by REWARD-PRECISION)
(define-constant REPUTATION-SCALE u100) ;; Scale for reputation scores (0-100)

;; Data structures

;; Node data - stores information about registered nodes
(define-map nodes
  { node-id: (buff 32) }
  {
    owner: principal,
    reputation: uint,
    last-claim-height: uint,
    total-rewards-claimed: uint,
    active: bool
  }
)

;; Reputation factors - weights for different performance metrics
(define-data-var reputation-weights
  {
    uptime-weight: uint,
    quality-weight: uint, 
    contribution-weight: uint
  }
  {
    uptime-weight: u50,      ;; 50% weight for uptime
    quality-weight: u30,     ;; 30% weight for data quality
    contribution-weight: u20 ;; 20% weight for network contribution
  }
)

;; Track pending rewards for each node
(define-map pending-rewards
  { node-id: (buff 32) }
  { amount: uint }
)

;; Global statistics
(define-data-var total-rewards-distributed uint u0)
(define-data-var active-nodes uint u0)

;; Private functions

;; Calculate reputation score based on node performance metrics
(define-private (calculate-reputation (uptime uint) (quality uint) (contribution uint))
  (let
    (
      (weights (var-get reputation-weights))
      (uptime-score (/ (* uptime (get uptime-weight weights)) u100))
      (quality-score (/ (* quality (get quality-weight weights)) u100))
      (contribution-score (/ (* contribution (get contribution-weight weights)) u100))
    )
    (+ (+ uptime-score quality-score) contribution-score)
  )
)

;; Calculate reward amount based on reputation and base rate
(define-private (calculate-reward (reputation uint) (blocks-since-claim uint))
  (let
    (
      (reputation-multiplier (+ u500 (* reputation u5))) ;; 0.5x to 5.5x multiplier based on reputation
      (raw-reward (* (* BASE-REWARD-RATE blocks-since-claim) reputation-multiplier))
    )
    (/ raw-reward u1000) ;; Adjust by multiplier scale
  )
)

;; Check if node exists and is owned by the sender
(define-private (check-node-owner (node-id (buff 32)))
  (match (map-get? nodes { node-id: node-id })
    node (is-eq (get owner node) tx-sender)
    false
  )
)


;; Read-only functions

;; Get node details
(define-read-only (get-node-info (node-id (buff 32)))
  (map-get? nodes { node-id: node-id })
)

;; Get pending rewards for a node
(define-read-only (get-pending-rewards (node-id (buff 32)))
  (default-to { amount: u0 } (map-get? pending-rewards { node-id: node-id }))
)

;; Check if a node can claim rewards (cooldown period has passed)
(define-read-only (can-claim-rewards (node-id (buff 32)))
  (match (map-get? nodes { node-id: node-id })
    node (let
           (
             (last-claim (get last-claim-height node))
             (current-height block-height)
           )
           (>= (- current-height last-claim) MIN-CLAIM-COOLDOWN)
         )
    false
  )
)

;; Calculate estimated reward for a node if claimed now
(define-read-only (estimate-reward (node-id (buff 32)))
  (match (map-get? nodes { node-id: node-id })
    node (let
           (
             (reputation (get reputation node))
             (last-claim (get last-claim-height node))
             (current-height block-height)
             (blocks-since-claim (- current-height last-claim))
           )
           (if (< blocks-since-claim MIN-CLAIM-COOLDOWN)
             { can-claim: false, estimated-amount: u0 }
             { 
               can-claim: true, 
               estimated-amount: (+ 
                 (get amount (get-pending-rewards node-id))
                 (calculate-reward reputation blocks-since-claim)
               )
             }
           )
         )
    { can-claim: false, estimated-amount: u0 }
  )
)

;; Get global statistics
(define-read-only (get-statistics)
  {
    total-rewards-distributed: (var-get total-rewards-distributed),
    active-nodes: (var-get active-nodes)
  }
)

;; Public functions

;; Register a new node to the system
(define-public (register-node (node-id (buff 32)))
  (let
    (
      (node-exists (is-some (map-get? nodes { node-id: node-id })))
    )
    (asserts! (not node-exists) ERR-NODE-ALREADY-REGISTERED)
    (map-set nodes
      { node-id: node-id }
      {
        owner: tx-sender,
        reputation: u50, ;; Start with neutral reputation
        last-claim-height: block-height,
        total-rewards-claimed: u0,
        active: true
      }
    )
    (var-set active-nodes (+ (var-get active-nodes) u1))
    (ok true)
  )
)


;; Claim rewards for a node
(define-public (claim-rewards (node-id (buff 32)))
  (let
    (
      (node-opt (map-get? nodes { node-id: node-id }))
      (pending (get-pending-rewards node-id))
    )
    ;; Validate claim
    (asserts! (is-some node-opt) ERR-NODE-NOT-FOUND)
    (let
      (
        (node (unwrap! node-opt ERR-NODE-NOT-FOUND))
        (current-height block-height)
        (last-claim (get last-claim-height node))
        (blocks-since-claim (- current-height last-claim))
      )
      (asserts! (check-node-owner node-id) ERR-NOT-AUTHORIZED)
      (asserts! (>= blocks-since-claim MIN-CLAIM-COOLDOWN) ERR-COOLDOWN-ACTIVE)
      
      ;; Calculate reward
      (let
        (
          (reputation (get reputation node))
          (new-reward (calculate-reward reputation blocks-since-claim))
          (total-reward (+ new-reward (get amount pending)))
        )
        (asserts! (> total-reward u0) ERR-NO-REWARDS)
        
        ;; Update storage
        (map-set nodes
          { node-id: node-id }
          (merge node {
            last-claim-height: current-height,
            total-rewards-claimed: (+ (get total-rewards-claimed node) total-reward)
          })
        )
        (map-delete pending-rewards { node-id: node-id })
        (var-set total-rewards-distributed (+ (var-get total-rewards-distributed) total-reward))
        
        ;; TODO: Implement actual token transfer here
        ;; This would call a fungible token contract to transfer the reward tokens
        ;; For example: (contract-call? .token-contract transfer total-reward tx-sender (get owner node))
        
        (ok total-reward)
      )
    )
  )
)

;; Add bonus rewards to a node (administrative function)
(define-public (add-bonus-rewards (node-id (buff 32)) (amount uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? nodes { node-id: node-id })) ERR-NODE-NOT-FOUND)
    
    (let
      (
        (current-pending (get-pending-rewards node-id))
        (new-amount (+ (get amount current-pending) amount))
      )
      (map-set pending-rewards
        { node-id: node-id }
        { amount: new-amount }
      )
      (ok new-amount)
    )
  )
)

;; Update reputation weights (administrative function)
(define-public (update-reputation-weights (uptime-weight uint) (quality-weight uint) (contribution-weight uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (+ (+ uptime-weight quality-weight) contribution-weight) u100) (err u109))
    
    (var-set reputation-weights {
      uptime-weight: uptime-weight,
      quality-weight: quality-weight,
      contribution-weight: contribution-weight
    })
    (ok true)
  )
)

;; Deactivate a node (can be called by owner or admin)
(define-public (deactivate-node (node-id (buff 32)))
  (let
    (
      (node-opt (map-get? nodes { node-id: node-id }))
    )
    (asserts! (is-some node-opt) ERR-NODE-NOT-FOUND)
    (let
      (
        (node (unwrap-panic node-opt))
      )
      (asserts! (or (is-eq tx-sender CONTRACT-OWNER) (is-eq tx-sender (get owner node))) ERR-NOT-AUTHORIZED)
      
      (map-set nodes
        { node-id: node-id }
        (merge node { active: false })
      )
      (var-set active-nodes (- (var-get active-nodes) u1))
      (ok true)
    )
  )
)