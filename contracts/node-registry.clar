;; node-registry
;; 
;; This contract manages the registration, verification, and lifecycle tracking of IoT nodes
;; in the Loop-Node network. It provides a decentralized and transparent way to maintain
;; a registry of all authorized IoT nodes, their ownership, status, and relevant metadata.
;; The registry serves as a source of truth for node legitimacy in the network.

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NODE-NOT-FOUND (err u101))
(define-constant ERR-NODE-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-NOT-NODE-OWNER (err u104))
(define-constant ERR-METADATA-TOO-LARGE (err u105))

;; Node status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-INACTIVE u2)
(define-constant STATUS-SUSPENDED u3)

;; Maximum metadata length (in bytes)
(define-constant MAX-METADATA-LENGTH u1024)

;; Data structures

;; Node structure containing all relevant information about an IoT node
(define-map nodes 
  { node-id: (buff 32) }
  {
    owner: principal,
    status: uint,
    location: (optional (tuple (latitude (string-utf8 40)) (longitude (string-utf8 40)))),
    capabilities: (list 10 (string-utf8 64)),
    firmware-version: (string-utf8 32),
    registration-time: uint,
    last-updated: uint,
    metadata: (buff 1024)
  }
)

;; Track nodes by owner to enable faster lookups
(define-map nodes-by-owner
  { owner: principal }
  { node-ids: (list 100 (buff 32)) }
)

;; Counters for network statistics
(define-data-var total-nodes uint u0)
(define-data-var active-nodes uint u0)

;; Contract owner for administrative operations
(define-data-var contract-admin principal tx-sender)

;; Private functions

;; Update node counts based on status changes
(define-private (update-node-count (old-status uint) (new-status uint))
  (begin
    ;; Decrement active count if node was previously active
    (if (is-eq old-status STATUS-ACTIVE)
        (var-set active-nodes (- (var-get active-nodes) u1))
        true)
    ;; Increment active count if node is becoming active
    (if (is-eq new-status STATUS-ACTIVE)
        (var-set active-nodes (+ (var-get active-nodes) u1))
        true)
  )
)


;; Validate node status is one of the defined constants
(define-private (is-valid-status (status uint))
  (or 
    (is-eq status STATUS-ACTIVE)
    (is-eq status STATUS-INACTIVE)
    (is-eq status STATUS-SUSPENDED)
  )
)

;; Check if principal is the node owner
(define-private (is-node-owner (node-id (buff 32)) (owner principal))
  (match (map-get? nodes { node-id: node-id })
    node (is-eq (get owner node) owner)
    false
  )
)

;; Public functions


;; Update node status (active, inactive, suspended)
(define-public (update-node-status (node-id (buff 32)) (new-status uint))
  (let (
    (node (unwrap! (map-get? nodes { node-id: node-id }) ERR-NODE-NOT-FOUND))
    (old-status (get status node))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check authorization
    (asserts! (is-node-owner node-id tx-sender) ERR-NOT-NODE-OWNER)
    ;; Validate status value
    (asserts! (is-valid-status new-status) ERR-INVALID-STATUS)
    
    ;; Update node status
    (map-set nodes
      { node-id: node-id }
      (merge node { 
        status: new-status,
        last-updated: current-time
      })
    )
    
    ;; Update counters
    (update-node-count old-status new-status)
    
    (ok true)
  )
)

;; Update node metadata
(define-public (update-node-metadata 
    (node-id (buff 32))
    (firmware-version (string-utf8 32))
    (metadata (buff 1024))
  )
  (let (
    (node (unwrap! (map-get? nodes { node-id: node-id }) ERR-NODE-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check authorization
    (asserts! (is-node-owner node-id tx-sender) ERR-NOT-NODE-OWNER)
    ;; Check metadata size
    (asserts! (<= (len metadata) MAX-METADATA-LENGTH) ERR-METADATA-TOO-LARGE)
    
    ;; Update node metadata
    (map-set nodes
      { node-id: node-id }
      (merge node { 
        firmware-version: firmware-version,
        metadata: metadata,
        last-updated: current-time
      })
    )
    
    (ok true)
  )
)

;; Update node location
(define-public (update-node-location 
    (node-id (buff 32))
    (location (optional (tuple (latitude (string-utf8 40)) (longitude (string-utf8 40)))))
  )
  (let (
    (node (unwrap! (map-get? nodes { node-id: node-id }) ERR-NODE-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check authorization
    (asserts! (is-node-owner node-id tx-sender) ERR-NOT-NODE-OWNER)
    
    ;; Update node location
    (map-set nodes
      { node-id: node-id }
      (merge node { 
        location: location,
        last-updated: current-time
      })
    )
    
    (ok true)
  )
)

;; Update node capabilities
(define-public (update-node-capabilities 
    (node-id (buff 32))
    (capabilities (list 10 (string-utf8 64)))
  )
  (let (
    (node (unwrap! (map-get? nodes { node-id: node-id }) ERR-NODE-NOT-FOUND))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check authorization
    (asserts! (is-node-owner node-id tx-sender) ERR-NOT-NODE-OWNER)
    
    ;; Update node capabilities
    (map-set nodes
      { node-id: node-id }
      (merge node { 
        capabilities: capabilities,
        last-updated: current-time
      })
    )
    
    (ok true)
  )
)

;; Read-only functions

;; Get node details by ID
(define-read-only (get-node (node-id (buff 32)))
  (map-get? nodes { node-id: node-id })
)

;; Check if node is active
(define-read-only (is-node-active (node-id (buff 32)))
  (match (map-get? nodes { node-id: node-id })
    node (is-eq (get status node) STATUS-ACTIVE)
    false
  )
)

;; Get all nodes owned by a principal
(define-read-only (get-nodes-by-owner (owner principal))
  (match (map-get? nodes-by-owner { owner: owner })
    owned-nodes (get node-ids owned-nodes)
    (list)
  )
)

;; Get network statistics
(define-read-only (get-network-stats)
  {
    total-nodes: (var-get total-nodes),
    active-nodes: (var-get active-nodes)
  }
)

;; Administrative functions

;; Set a new contract administrator
(define-public (set-contract-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    (var-set contract-admin new-admin)
    (ok true)
  )
)

;; Suspend a node (can only be called by contract admin)
(define-public (admin-suspend-node (node-id (buff 32)))
  (let (
    (node (unwrap! (map-get? nodes { node-id: node-id }) ERR-NODE-NOT-FOUND))
    (old-status (get status node))
    (current-time (unwrap-panic (get-block-info? time u0)))
  )
    ;; Check if caller is admin
    (asserts! (is-eq tx-sender (var-get contract-admin)) ERR-NOT-AUTHORIZED)
    
    ;; Suspend the node
    (map-set nodes
      { node-id: node-id }
      (merge node { 
        status: STATUS-SUSPENDED,
        last-updated: current-time
      })
    )
    
    ;; Update counters
    (update-node-count old-status STATUS-SUSPENDED)
    
    (ok true)
  )
)