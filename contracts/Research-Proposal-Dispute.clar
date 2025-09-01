(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_VOTED (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u105))
(define-constant ERR_DISPUTE_ALREADY_EXISTS (err u201))
(define-constant ERR_DISPUTE_NOT_FOUND (err u202))
(define-constant ERR_INSUFFICIENT_STAKE (err u203))
(define-constant ERR_DISPUTE_RESOLVED (err u204))
(define-constant ERR_CANNOT_DISPUTE_OWN_PROPOSAL (err u205))

(define-data-var dispute-counter uint u0)
(define-data-var dispute-stake-amount uint u1000)

(define-map proposal-disputes
  { proposal-id: uint }
  {
    dispute-id: uint,
    challenger: principal,
    reason: (string-ascii 200),
    stake-amount: uint,
    status: (string-ascii 20),
    escalated-votes-for: uint,
    escalated-votes-against: uint,
    resolution-block: uint
  })

(define-map dispute-votes
  { dispute-id: uint, reviewer: principal }
  { vote: bool })

(define-public (dispute-proposal (proposal-id uint) (reason (string-ascii 200)))
  (let ((proposal (unwrap! (contract-call? .Decentralized-Research get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (stake (var-get dispute-stake-amount))
        (dispute-id (+ (var-get dispute-counter) u1)))
    (asserts! (not (is-eq (get researcher proposal) tx-sender)) ERR_CANNOT_DISPUTE_OWN_PROPOSAL)
    (asserts! (is-eq (get status proposal) "approved") ERR_PROPOSAL_NOT_APPROVED)
    (asserts! (is-none (map-get? proposal-disputes { proposal-id: proposal-id })) ERR_DISPUTE_ALREADY_EXISTS)
    (asserts! (>= (stx-get-balance tx-sender) stake) ERR_INSUFFICIENT_STAKE)
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))
    (map-set proposal-disputes
      { proposal-id: proposal-id }
      {
        dispute-id: dispute-id,
        challenger: tx-sender,
        reason: reason,
        stake-amount: stake,
        status: "active",
        escalated-votes-for: u0,
        escalated-votes-against: u0,
        resolution-block: (+ stacks-block-height u288)
      })
    (var-set dispute-counter dispute-id)
    (ok dispute-id)))

(define-public (vote-on-dispute (proposal-id uint) (support-proposal bool))
  (let ((dispute (unwrap! (map-get? proposal-disputes { proposal-id: proposal-id }) ERR_DISPUTE_NOT_FOUND))
        (reviewer-info (unwrap! (contract-call? .Decentralized-Research get-reviewer-info tx-sender) ERR_NOT_AUTHORIZED)))
    (asserts! (get is-reviewer reviewer-info) ERR_NOT_AUTHORIZED)
    (asserts! (>= (get reputation reviewer-info) u20) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status dispute) "active") ERR_DISPUTE_RESOLVED)
    (asserts! (< stacks-block-height (get resolution-block dispute)) ERR_VOTING_ENDED)
    (asserts! (is-none (map-get? dispute-votes { dispute-id: (get dispute-id dispute), reviewer: tx-sender })) ERR_ALREADY_VOTED)
    (map-set dispute-votes
      { dispute-id: (get dispute-id dispute), reviewer: tx-sender }
      { vote: support-proposal })
    (map-set proposal-disputes
      { proposal-id: proposal-id }
      (merge dispute
        {
          escalated-votes-for: (if support-proposal (+ (get escalated-votes-for dispute) u1) (get escalated-votes-for dispute)),
          escalated-votes-against: (if support-proposal (get escalated-votes-against dispute) (+ (get escalated-votes-against dispute) u1))
        }))
    (ok true)))

(define-public (resolve-dispute (proposal-id uint))
  (let ((dispute (unwrap! (map-get? proposal-disputes { proposal-id: proposal-id }) ERR_DISPUTE_NOT_FOUND))
        (proposal (unwrap! (contract-call? .Decentralized-Research get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND)))
    (asserts! (>= stacks-block-height (get resolution-block dispute)) ERR_VOTING_ENDED)
    (asserts! (is-eq (get status dispute) "active") ERR_DISPUTE_RESOLVED)
    (let ((dispute-successful (> (get escalated-votes-against dispute) (get escalated-votes-for dispute))))
      (if dispute-successful
        (begin
          (try! (as-contract (stx-transfer? (get stake-amount dispute) tx-sender (get challenger dispute))))
          (map-set proposal-disputes { proposal-id: proposal-id } (merge dispute { status: "upheld" })))
        (begin
          (map-set proposal-disputes { proposal-id: proposal-id } (merge dispute { status: "rejected" }))))
      (ok dispute-successful))))

(define-read-only (get-dispute (proposal-id uint))
  (map-get? proposal-disputes { proposal-id: proposal-id }))

(define-read-only (get-dispute-vote (dispute-id uint) (reviewer principal))
  (map-get? dispute-votes { dispute-id: dispute-id, reviewer: reviewer }))