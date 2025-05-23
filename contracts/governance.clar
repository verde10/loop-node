;; governance.clar
;; A decentralized governance system for the IoT node network that enables stakeholders
;; to propose, vote on, and implement protocol changes, parameter adjustments, and 
;; node authorization policies in a transparent and democratic manner.

;; -----------------------------------------------
;; Constants and Error Codes
;; -----------------------------------------------

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PROPOSAL-EXISTS (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-PROPOSAL-EXPIRED (err u103))
(define-constant ERR-PROPOSAL-NOT-ACTIVE (err u104))
(define-constant ERR-ALREADY-VOTED (err u105))
(define-constant ERR-INSUFFICIENT-STAKE (err u106))
(define-constant ERR-VOTING-PERIOD-ACTIVE (err u107))
(define-constant ERR-PROPOSAL-NOT-APPROVED (err u108))
(define-constant ERR-INVALID-PROPOSAL-TYPE (err u109))
(define-constant ERR-INVALID-PARAMETER (err u110))

;; Governance parameters
(define-constant VOTING_PERIOD_BLOCKS u144) ;; Approximately 1 day (~10 min blocks)
(define-constant MIN_PROPOSAL_STAKE u10000000) ;; Minimum stake to create a proposal (10 tokens assuming 8 decimal places)
(define-constant APPROVAL_THRESHOLD u60) ;; 60% threshold for approval

;; Proposal types
(define-constant PROPOSAL-TYPE-PARAMETER u1)
(define-constant PROPOSAL-TYPE-PROTOCOL u2)
(define-constant PROPOSAL-TYPE-AUTHORIZATION u3)

;; -----------------------------------------------
;; Data Maps and Variables
;; -----------------------------------------------

;; Track proposal details
(define-map proposals
  { proposal-id: uint }
  {
    proposer: principal,
    title: (string-ascii 100),
    description: (string-utf8 1000),
    proposal-type: uint,
    parameter-key: (optional (string-ascii 50)),
    parameter-value: (optional (string-utf8 200)),
    contract-change: (optional (string-ascii 50)),
    created-at-block: uint,
    expires-at-block: uint,
    executed: bool,
    total-votes-for: uint,
    total-votes-against: uint,
    total-voting-power: uint
  }
)

;; Track who has voted on which proposal
(define-map proposal-votes
  { proposal-id: uint, voter: principal }
  {
    vote: bool,  ;; true = for, false = against
    voting-power: uint
  }
)

;; Track the voting power (stake) of each participant
(define-map voting-power
  { participant: principal }
  { power: uint }
)

;; Admin contract or principal for initial setup and emergency functions
(define-data-var governance-admin principal tx-sender)

;; Counter for proposal IDs
(define-data-var next-proposal-id uint u1)

;; -----------------------------------------------
;; Private Functions
;; -----------------------------------------------

;; Get current block height
(define-private (get-current-block-height)
  block-height
)

;; Check if a proposal is active (in voting period)
(define-private (is-proposal-active (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) false))
    (current-block (get-current-block-height))
  )
    (and 
      (>= current-block (get created-at-block proposal))
      (<= current-block (get expires-at-block proposal))
      (not (get executed proposal))
    )
  )
)

;; Check if a proposal has passed the approval threshold
(define-private (is-proposal-approved (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) false))
    (votes-for (get total-votes-for proposal))
    (total-votes (+ (get total-votes-for proposal) (get total-votes-against proposal)))
  )
    (if (> total-votes u0)
      (>= (* votes-for u100) (* total-votes APPROVAL_THRESHOLD))
      false
    )
  )
)

;; Calculate voting power for a participant (to be expanded based on token economics)
(define-private (calculate-voting-power (participant principal))
  (default-to 
    u0 
    (get power (map-get? voting-power { participant: participant }))
  )
)

;; Execute a parameter change proposal
(define-private (execute-parameter-proposal 
  (parameter-key (string-ascii 50)) 
  (parameter-value (string-utf8 200)))
  ;; Implementation depends on specific parameters to be governed
  ;; This is a placeholder and should be expanded for real parameters
  (ok true)
)

;; Execute a protocol change proposal
(define-private (execute-protocol-proposal (contract-change (string-ascii 50)))
  ;; Protocol upgrade logic would go here
  ;; This might involve triggering upgrades in other contracts or changing protocol parameters
  (ok true)
)

;; Execute an authorization policy change proposal
(define-private (execute-authorization-proposal (policy-change (string-utf8 200)))
  ;; Changes to node authorization policies would be implemented here
  (ok true)
)

;; -----------------------------------------------
;; Read-Only Functions
;; -----------------------------------------------

;; Get proposal details
(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id })
)

;; Get vote details for a specific voter on a proposal
(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })
)

;; Get voting power for a participant
(define-read-only (get-participant-voting-power (participant principal))
  (calculate-voting-power participant)
)

;; Check if a proposal is currently active for voting
(define-read-only (check-proposal-active (proposal-id uint))
  (is-proposal-active proposal-id)
)

;; Check if a proposal has been approved
(define-read-only (check-proposal-approved (proposal-id uint))
  (is-proposal-approved proposal-id)
)

;; Get the total number of proposals
(define-read-only (get-proposal-count)
  (- (var-get next-proposal-id) u1)
)

;; -----------------------------------------------
;; Public Functions
;; -----------------------------------------------


;; Create a new governance proposal
(define-public (create-proposal 
  (title (string-ascii 100))
  (description (string-utf8 1000))
  (proposal-type uint)
  (parameter-key (optional (string-ascii 50)))
  (parameter-value (optional (string-utf8 200)))
  (contract-change (optional (string-ascii 50)))
)
  (let (
    (proposer tx-sender)
    (proposer-stake (calculate-voting-power proposer))
    (proposal-id (var-get next-proposal-id))
    (current-block (get-current-block-height))
  )
    ;; Validate proposal type
    (asserts! (or (is-eq proposal-type PROPOSAL-TYPE-PARAMETER)
                 (is-eq proposal-type PROPOSAL-TYPE-PROTOCOL)
                 (is-eq proposal-type PROPOSAL-TYPE-AUTHORIZATION))
            ERR-INVALID-PROPOSAL-TYPE)
    
    ;; Check that proposer has sufficient stake
    (asserts! (>= proposer-stake MIN_PROPOSAL_STAKE) ERR-INSUFFICIENT-STAKE)
    
    ;; Store the proposal
    (map-set proposals
      { proposal-id: proposal-id }
      {
        proposer: proposer,
        title: title,
        description: description,
        proposal-type: proposal-type,
        parameter-key: parameter-key,
        parameter-value: parameter-value,
        contract-change: contract-change,
        created-at-block: current-block,
        expires-at-block: (+ current-block VOTING_PERIOD_BLOCKS),
        executed: false,
        total-votes-for: u0,
        total-votes-against: u0,
        total-voting-power: u0
      }
    )
    
    ;; Increment proposal ID counter
    (var-set next-proposal-id (+ proposal-id u1))
    
    (ok proposal-id)
  )
)

;; Vote on a proposal
(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let (
    (voter tx-sender)
    (voting-power-amount (calculate-voting-power voter))
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
  )
    ;; Check proposal is active
    (asserts! (is-proposal-active proposal-id) ERR-PROPOSAL-NOT-ACTIVE)
    
    ;; Check voter has voting power
    (asserts! (> voting-power-amount u0) ERR-INSUFFICIENT-STAKE)
    
    ;; Check voter hasn't already voted
    (asserts! (is-none (map-get? proposal-votes { proposal-id: proposal-id, voter: voter })) ERR-ALREADY-VOTED)
    
    ;; Record the vote
    (map-set proposal-votes
      { proposal-id: proposal-id, voter: voter }
      { 
        vote: vote-for,
        voting-power: voting-power-amount
      }
    )
    
    ;; Update proposal totals
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal 
        {
          total-votes-for: (if vote-for 
                              (+ (get total-votes-for proposal) voting-power-amount) 
                              (get total-votes-for proposal)),
          total-votes-against: (if vote-for 
                                  (get total-votes-against proposal) 
                                  (+ (get total-votes-against proposal) voting-power-amount)),
          total-voting-power: (+ (get total-voting-power proposal) voting-power-amount)
        }
      )
    )
    
    (ok true)
  )
)


;; Change governance admin - only callable by current admin
(define-public (set-governance-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get governance-admin)) ERR-NOT-AUTHORIZED)
    (var-set governance-admin new-admin)
    (ok true)
  )
)

;; Emergency cancel proposal - only for admin use in case of critical issues
(define-public (emergency-cancel-proposal (proposal-id uint))
  (let (
    (proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR-PROPOSAL-NOT-FOUND))
  )
    (asserts! (is-eq tx-sender (var-get governance-admin)) ERR-NOT-AUTHORIZED)
    (asserts! (not (get executed proposal)) ERR-PROPOSAL-EXPIRED)
    
    ;; Mark as executed to prevent normal execution
    (map-set proposals
      { proposal-id: proposal-id }
      (merge proposal { executed: true })
    )
    
    (ok true)
  )
)