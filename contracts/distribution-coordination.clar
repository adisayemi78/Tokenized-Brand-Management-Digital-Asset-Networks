;; Distribution Coordination Contract
;; Coordinates asset distribution workflows and approvals

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u500))
(define-constant err-not-found (err u501))
(define-constant err-unauthorized (err u502))
(define-constant err-invalid-status (err u503))
(define-constant err-already-approved (err u504))

;; Data Variables
(define-data-var next-request-id uint u1)
(define-data-var next-workflow-id uint u1)

;; Data Maps
(define-map distribution-requests
  { request-id: uint }
  {
    asset-id: uint,
    requester: principal,
    target-platform: (string-ascii 50),
    purpose: (string-ascii 200),
    status: (string-ascii 20),
    requested-at: uint,
    approved-by: (optional principal),
    approved-at: (optional uint),
    notes: (string-ascii 500)
  }
)

(define-map distribution-workflows
  { workflow-id: uint }
  {
    name: (string-ascii 100),
    steps: (list 10 (string-ascii 50)),
    approvers: (list 5 principal),
    auto-approve: bool,
    created-by: principal,
    active: bool
  }
)

(define-map asset-distributions
  { asset-id: uint, platform: (string-ascii 50) }
  {
    distributed-by: principal,
    distributed-at: uint,
    status: (string-ascii 20),
    download-count: uint,
    last-accessed: uint
  }
)

(define-map approval-history
  { request-id: uint, approver: principal }
  {
    decision: (string-ascii 20),
    timestamp: uint,
    comments: (string-ascii 500)
  }
)

;; Public Functions

;; Submit distribution request
(define-public (submit-distribution-request
  (asset-id uint)
  (target-platform (string-ascii 50))
  (purpose (string-ascii 200))
)
  (let ((request-id (var-get next-request-id)))
    (map-set distribution-requests
      { request-id: request-id }
      {
        asset-id: asset-id,
        requester: tx-sender,
        target-platform: target-platform,
        purpose: purpose,
        status: "pending",
        requested-at: block-height,
        approved-by: none,
        approved-at: none,
        notes: ""
      }
    )

    (var-set next-request-id (+ request-id u1))
    (ok request-id)
  )
)

;; Approve distribution request
(define-public (approve-request (request-id uint) (notes (string-ascii 500)))
  (let ((request (unwrap! (map-get? distribution-requests { request-id: request-id }) err-not-found)))
    (asserts! (is-eq (get status request) "pending") err-invalid-status)

    ;; Record approval decision
    (map-set approval-history
      { request-id: request-id, approver: tx-sender }
      {
        decision: "approved",
        timestamp: block-height,
        comments: notes
      }
    )

    ;; Update request status
    (map-set distribution-requests
      { request-id: request-id }
      (merge request {
        status: "approved",
        approved-by: (some tx-sender),
        approved-at: (some block-height),
        notes: notes
      })
    )

    ;; Create distribution record
    (create-distribution-record (get asset-id request) (get target-platform request))
    (ok true)
  )
)

;; Reject distribution request
(define-public (reject-request (request-id uint) (reason (string-ascii 500)))
  (let ((request (unwrap! (map-get? distribution-requests { request-id: request-id }) err-not-found)))
    (asserts! (is-eq (get status request) "pending") err-invalid-status)

    ;; Record rejection decision
    (map-set approval-history
      { request-id: request-id, approver: tx-sender }
      {
        decision: "rejected",
        timestamp: block-height,
        comments: reason
      }
    )

    ;; Update request status
    (map-set distribution-requests
      { request-id: request-id }
      (merge request {
        status: "rejected",
        notes: reason
      })
    )
    (ok true)
  )
)

;; Create distribution workflow
(define-public (create-workflow
  (name (string-ascii 100))
  (steps (list 10 (string-ascii 50)))
  (approvers (list 5 principal))
  (auto-approve bool)
)
  (let ((workflow-id (var-get next-workflow-id)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)

    (map-set distribution-workflows
      { workflow-id: workflow-id }
      {
        name: name,
        steps: steps,
        approvers: approvers,
        auto-approve: auto-approve,
        created-by: tx-sender,
        active: true
      }
    )

    (var-set next-workflow-id (+ workflow-id u1))
    (ok workflow-id)
  )
)

;; Record asset download/access
(define-public (record-access (asset-id uint) (platform (string-ascii 50)))
  (let ((distribution (map-get? asset-distributions { asset-id: asset-id, platform: platform })))
    (match distribution
      dist (map-set asset-distributions
             { asset-id: asset-id, platform: platform }
             (merge dist {
               download-count: (+ (get download-count dist) u1),
               last-accessed: block-height
             }))
      ;; If no distribution record exists, this shouldn't happen
      false
    )
    (ok true)
  )
)

;; Private Functions

;; Create distribution record after approval
(define-private (create-distribution-record (asset-id uint) (platform (string-ascii 50)))
  (map-set asset-distributions
    { asset-id: asset-id, platform: platform }
    {
      distributed-by: tx-sender,
      distributed-at: block-height,
      status: "active",
      download-count: u0,
      last-accessed: u0
    }
  )
)

;; Read-only Functions

;; Get distribution request
(define-read-only (get-distribution-request (request-id uint))
  (map-get? distribution-requests { request-id: request-id })
)

;; Get distribution workflow
(define-read-only (get-workflow (workflow-id uint))
  (map-get? distribution-workflows { workflow-id: workflow-id })
)

;; Get asset distribution info
(define-read-only (get-asset-distribution (asset-id uint) (platform (string-ascii 50)))
  (map-get? asset-distributions { asset-id: asset-id, platform: platform })
)

;; Get approval history for request
(define-read-only (get-approval-history (request-id uint) (approver principal))
  (map-get? approval-history { request-id: request-id, approver: approver })
)

;; Check if asset is distributed on platform
(define-read-only (is-asset-distributed (asset-id uint) (platform (string-ascii 50)))
  (is-some (map-get? asset-distributions { asset-id: asset-id, platform: platform }))
)

;; Get distribution status
(define-read-only (get-distribution-status (asset-id uint) (platform (string-ascii 50)))
  (match (map-get? asset-distributions { asset-id: asset-id, platform: platform })
    distribution (get status distribution)
    "not-distributed"
  )
)
