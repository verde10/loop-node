;; node-data-verification
;; 
;; This contract provides mechanisms to verify and validate data submitted by IoT nodes,
;; ensuring information hasn't been tampered with and comes from legitimate sources.
;; It implements a challenge-response system where nodes must prove their identity
;; when submitting data, maintains audit logs of data submissions, and allows the
;; community to flag suspicious activities.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NODE-NOT-REGISTERED (err u101))
(define-constant ERR-INVALID-CHALLENGE (err u102))
(define-constant ERR-CHALLENGE-EXPIRED (err u103))
(define-constant ERR-INVALID-RESPONSE (err u104))
(define-constant ERR-DATA-ALREADY-SUBMITTED (err u105))
(define-constant ERR-INVALID-DATA-FORMAT (err u106))
(define-constant ERR-NO-ACTIVE-CHALLENGE (err u107))
(define-constant ERR-ALREADY-FLAGGED (err u108))
(define-constant ERR-FLAG-NOT-FOUND (err u109))
(define-constant ERR-SUBMISSION-NOT-FOUND (err u110))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant CHALLENGE-VALIDITY-BLOCKS u10) ;; Number of blocks a challenge remains valid

;; Data structures
;; Map of registered nodes - must be registered in a separate registration contract
(define-map registered-nodes principal bool)

;; Map of active challenges for nodes
(define-map node-challenges 
  { node: principal } 
  { challenge: (buff 32), block-height: uint })

;; Map to store data submissions with verification status
(define-map data-submissions
  { submission-id: (buff 32) }
  { 
    node: principal,
    data-hash: (buff 32),
    timestamp: uint,
    block-height: uint,
    verified: bool,
    metadata: (optional (string-utf8 500))
  }
)

;; Map for submission history by node
(define-map node-submission-history
  { node: principal }
  { submission-ids: (list 100 (buff 32)) }
)

;; Map for flagged submissions
(define-map flagged-submissions
  { submission-id: (buff 32), flagger: principal }
  { 
    reason: (string-utf8 200),
    timestamp: uint,
    resolved: bool
  }
)

;; Public counter for submission IDs
(define-data-var submission-counter uint u0)

;; Private functions

;; Add a submission ID to a node's history
(define-private (add-to-node-history (node principal) (submission-id (buff 32)))
  (let ((current-history (default-to { submission-ids: (list) } (map-get? node-submission-history { node: node }))))
    (map-set node-submission-history
      { node: node }
      { submission-ids: (unwrap-panic (as-max-len? (append (get submission-ids current-history) submission-id) u100)) }
    )
  )
)


;; Validate if a challenge is still active
(define-private (is-challenge-valid (challenge-info { challenge: (buff 32), block-height: uint }))
  (< (- block-height (get block-height challenge-info)) CHALLENGE-VALIDITY-BLOCKS)
)

;; Read-only functions

;; Check if a node is registered
(define-read-only (is-node-registered (node principal))
  (default-to false (map-get? registered-nodes node))
)

;; Get active challenge for a node
(define-read-only (get-node-challenge (node principal))
  (map-get? node-challenges { node: node })
)

;; Get data submission details
(define-read-only (get-data-submission (submission-id (buff 32)))
  (map-get? data-submissions { submission-id: submission-id })
)

;; Get a node's submission history
(define-read-only (get-node-submission-history (node principal))
  (default-to { submission-ids: (list) } (map-get? node-submission-history { node: node }))
)

;; Check if a submission is flagged by a specific user
(define-read-only (is-submission-flagged (submission-id (buff 32)) (flagger principal))
  (is-some (map-get? flagged-submissions { submission-id: submission-id, flagger: flagger }))
)

;; Get flag details
(define-read-only (get-flag-details (submission-id (buff 32)) (flagger principal))
  (map-get? flagged-submissions { submission-id: submission-id, flagger: flagger })
)

;; Public functions

;; Register a node (typically called by a registration contract)
(define-public (register-node (node principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set registered-nodes node true))
  )
)



;; Flag a suspicious data submission
(define-public (flag-submission (submission-id (buff 32)) (reason (string-utf8 200)))
  (begin
    ;; Verify submission exists
    (asserts! (is-some (get-data-submission submission-id)) ERR-SUBMISSION-NOT-FOUND)
    
    ;; Check if already flagged by this user
    (asserts! (not (is-submission-flagged submission-id tx-sender)) ERR-ALREADY-FLAGGED)
    
    ;; Record the flag
    (map-set flagged-submissions
      { submission-id: submission-id, flagger: tx-sender }
      { 
        reason: reason,
        timestamp: (unwrap-panic (get-block-info? time block-height)),
        resolved: false
      }
    )
    
    (ok true)
  )
)

;; Resolve a flagged submission (only contract owner can do this)
(define-public (resolve-flag (submission-id (buff 32)) (flagger principal) (is-valid bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    
    (let ((flag (unwrap! (map-get? flagged-submissions { submission-id: submission-id, flagger: flagger }) ERR-FLAG-NOT-FOUND))
          (submission (unwrap! (map-get? data-submissions { submission-id: submission-id }) ERR-SUBMISSION-NOT-FOUND)))
      
      ;; Update flag status
      (map-set flagged-submissions
        { submission-id: submission-id, flagger: flagger }
        (merge flag { resolved: true })
      )
      
      ;; Update submission verification status if needed
      (if (not is-valid)
        (map-set data-submissions
          { submission-id: submission-id }
          (merge submission { verified: false })
        )
        true
      )
      
      (ok is-valid)
    )
  )
)