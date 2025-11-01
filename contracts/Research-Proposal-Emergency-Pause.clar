(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_VOTED (err u102))
(define-constant ERR_PAUSE_NOT_FOUND (err u400))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u401))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u402))
(define-constant ERR_ALREADY_PAUSED (err u403))
(define-constant ERR_NOT_PAUSED (err u404))
(define-constant ERR_PAUSE_EXPIRED (err u405))

(define-data-var pause-counter uint u0)
(define-data-var min-reputation-to-pause uint u30)
(define-data-var pause-duration uint u1008)

(define-map emergency-pauses
  { proposal-id: uint }
  {
    pause-id: uint,
    initiator: principal,
    reason: (string-ascii 300),
    pause-start-block: uint,
    pause-end-block: uint,
    status: (string-ascii 20),
    support-votes: uint,
    oppose-votes: uint,
    required-votes: uint
  })

(define-map pause-votes
  { pause-id: uint, reviewer: principal }
  { supports-pause: bool })

(define-public (emergency-pause-proposal (proposal-id uint) (reason (string-ascii 300)))
  (let ((proposal (unwrap! (contract-call? .Decentralized-Research get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (reviewer-info (unwrap! (contract-call? .Decentralized-Research get-reviewer-info tx-sender) ERR_NOT_AUTHORIZED))
        (pause-id (+ (var-get pause-counter) u1)))
    (asserts! (get is-reviewer reviewer-info) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get reputation reviewer-info) (var-get min-reputation-to-pause)) ERR_INSUFFICIENT_REPUTATION)
    (asserts! (is-eq (get status proposal) "approved") ERR_PROPOSAL_NOT_APPROVED)
    (asserts! (not (get funded proposal)) ERR_PROPOSAL_NOT_FOUND)
    (asserts! (is-none (map-get? emergency-pauses { proposal-id: proposal-id })) ERR_ALREADY_PAUSED)
    (map-set emergency-pauses
      { proposal-id: proposal-id }
      {
        pause-id: pause-id,
        initiator: tx-sender,
        reason: reason,
        pause-start-block: stacks-block-height,
        pause-end-block: (+ stacks-block-height (var-get pause-duration)),
        status: "active",
        support-votes: u1,
        oppose-votes: u0,
        required-votes: u3
      })
    (map-set pause-votes
      { pause-id: pause-id, reviewer: tx-sender }
      { supports-pause: true })
    (var-set pause-counter pause-id)
    (ok pause-id)))

(define-public (vote-on-pause (proposal-id uint) (support-pause bool))
  (let ((pause (unwrap! (map-get? emergency-pauses { proposal-id: proposal-id }) ERR_PAUSE_NOT_FOUND))
        (reviewer-info (unwrap! (contract-call? .Decentralized-Research get-reviewer-info tx-sender) ERR_NOT_AUTHORIZED)))
    (asserts! (get is-reviewer reviewer-info) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get reputation reviewer-info) u20) ERR_INSUFFICIENT_REPUTATION)
    (asserts! (is-eq (get status pause) "active") ERR_NOT_PAUSED)
    (asserts! (< stacks-block-height (get pause-end-block pause)) ERR_PAUSE_EXPIRED)
    (asserts! (is-none (map-get? pause-votes { pause-id: (get pause-id pause), reviewer: tx-sender })) ERR_ALREADY_VOTED)
    (map-set pause-votes
      { pause-id: (get pause-id pause), reviewer: tx-sender }
      { supports-pause: support-pause })
    (map-set emergency-pauses
      { proposal-id: proposal-id }
      (merge pause
        {
          support-votes: (if support-pause (+ (get support-votes pause) u1) (get support-votes pause)),
          oppose-votes: (if support-pause (get oppose-votes pause) (+ (get oppose-votes pause) u1))
        }))
    (ok true)))

(define-public (resolve-pause (proposal-id uint))
  (let ((pause (unwrap! (map-get? emergency-pauses { proposal-id: proposal-id }) ERR_PAUSE_NOT_FOUND)))
    (asserts! (is-eq (get status pause) "active") ERR_NOT_PAUSED)
    (let ((should-maintain-pause (>= (get support-votes pause) (get required-votes pause)))
          (should-lift-pause (>= (get oppose-votes pause) (get required-votes pause)))
          (time-expired (>= stacks-block-height (get pause-end-block pause))))
      (if (or should-maintain-pause time-expired)
        (begin
          (map-set emergency-pauses { proposal-id: proposal-id } (merge pause { status: "upheld" }))
          (ok "pause-maintained"))
        (if should-lift-pause
          (begin
            (map-set emergency-pauses { proposal-id: proposal-id } (merge pause { status: "lifted" }))
            (ok "pause-lifted"))
          ERR_NOT_PAUSED)))))

(define-read-only (is-proposal-paused (proposal-id uint))
  (match (map-get? emergency-pauses { proposal-id: proposal-id })
    pause (and (is-eq (get status pause) "active") (< stacks-block-height (get pause-end-block pause)))
    false))

(define-read-only (get-pause-details (proposal-id uint))
  (map-get? emergency-pauses { proposal-id: proposal-id }))

(define-read-only (get-pause-vote (pause-id uint) (reviewer principal))
  (map-get? pause-votes { pause-id: pause-id, reviewer: reviewer }))
