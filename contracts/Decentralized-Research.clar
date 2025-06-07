
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_VOTED (err u102))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_INSUFFICIENT_FUNDS (err u104))
(define-constant ERR_PROPOSAL_NOT_APPROVED (err u105))
(define-constant ERR_ALREADY_FUNDED (err u106))
(define-constant ERR_INVALID_AMOUNT (err u107))

(define-data-var proposal-counter uint u0)
(define-data-var total-treasury uint u0)

(define-map proposals
  { proposal-id: uint }
  {
    researcher: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    funding-amount: uint,
    votes-for: uint,
    votes-against: uint,
    voting-end-block: uint,
    status: (string-ascii 20),
    funded: bool
  }
)

(define-map votes
  { proposal-id: uint, voter: principal }
  { vote: bool }
)

(define-map researchers
  { researcher: principal }
  {
    reputation: uint,
    total-grants: uint,
    active-proposals: uint
  }
)

(define-map reviewer-status
  { reviewer: principal }
  { is-reviewer: bool, reputation: uint }
)

(define-public (add-funds)
  (let ((amount (stx-get-balance tx-sender)))
    (if (> amount u0)
      (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set total-treasury (+ (var-get total-treasury) amount))
        (ok amount))
      ERR_INVALID_AMOUNT)))

(define-public (register-reviewer)
  (begin
    (map-set reviewer-status
      { reviewer: tx-sender }
      { is-reviewer: true, reputation: u10 })
    (ok true)))

(define-public (submit-proposal (title (string-ascii 100)) (description (string-ascii 500)) (funding-amount uint))
  (let ((proposal-id (+ (var-get proposal-counter) u1)))
    (if (and (> funding-amount u0) (<= funding-amount (var-get total-treasury)))
      (begin
        (map-set proposals
          { proposal-id: proposal-id }
          {
            researcher: tx-sender,
            title: title,
            description: description,
            funding-amount: funding-amount,
            votes-for: u0,
            votes-against: u0,
            voting-end-block: (+ stacks-block-height u144),
            status: "pending",
            funded: false
          })
        (map-set researchers
          { researcher: tx-sender }
          (merge
            (default-to { reputation: u0, total-grants: u0, active-proposals: u0 }
                       (map-get? researchers { researcher: tx-sender }))
            { active-proposals: (+ (get active-proposals 
                                   (default-to { reputation: u0, total-grants: u0, active-proposals: u0 }
                                              (map-get? researchers { researcher: tx-sender }))) u1) }))
        (var-set proposal-counter proposal-id)
        (ok proposal-id))
      ERR_INVALID_AMOUNT)))

(define-public (vote-on-proposal (proposal-id uint) (vote-for bool))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        (reviewer-info (map-get? reviewer-status { reviewer: tx-sender })))
    (if (and 
          (is-some reviewer-info)
          (get is-reviewer (unwrap-panic reviewer-info))
          (< stacks-block-height (get voting-end-block proposal))
          (is-none (map-get? votes { proposal-id: proposal-id, voter: tx-sender })))
      (begin
        (map-set votes
          { proposal-id: proposal-id, voter: tx-sender }
          { vote: vote-for })
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal
            { 
              votes-for: (if vote-for (+ (get votes-for proposal) u1) (get votes-for proposal)),
              votes-against: (if vote-for (get votes-against proposal) (+ (get votes-against proposal) u1))
            }))
        (ok true))
      (if (>= stacks-block-height (get voting-end-block proposal))
        ERR_VOTING_ENDED
        (if (is-some (map-get? votes { proposal-id: proposal-id, voter: tx-sender }))
          ERR_ALREADY_VOTED
          ERR_NOT_AUTHORIZED)))))
(define-public (finalize-proposal (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND)))
    (if (>= stacks-block-height (get voting-end-block proposal))
      (let ((approved (> (get votes-for proposal) (get votes-against proposal))))
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal
            { status: (if approved "approved" "rejected") }))
        (ok approved))
      ERR_VOTING_ENDED)))

(define-public (claim-funding (proposal-id uint))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND)))
    (if (and 
          (is-eq (get researcher proposal) tx-sender)
          (is-eq (get status proposal) "approved")
          (not (get funded proposal))
          (>= (var-get total-treasury) (get funding-amount proposal)))
      (begin
        (try! (as-contract (stx-transfer? (get funding-amount proposal) tx-sender (get researcher proposal))))
        (var-set total-treasury (- (var-get total-treasury) (get funding-amount proposal)))
        (map-set proposals
          { proposal-id: proposal-id }
          (merge proposal { funded: true, status: "funded" }))
        (map-set researchers
          { researcher: tx-sender }
          (merge
            (default-to { reputation: u0, total-grants: u0, active-proposals: u0 }
                       (map-get? researchers { researcher: tx-sender }))
            { 
              total-grants: (+ (get total-grants 
                               (default-to { reputation: u0, total-grants: u0, active-proposals: u0 }
                                          (map-get? researchers { researcher: tx-sender }))) u1),
              reputation: (+ (get reputation 
                             (default-to { reputation: u0, total-grants: u0, active-proposals: u0 }
                                        (map-get? researchers { researcher: tx-sender }))) u5),
              active-proposals: (- (get active-proposals 
                                   (default-to { reputation: u0, total-grants: u0, active-proposals: u0 }
                                              (map-get? researchers { researcher: tx-sender }))) u1)
            }))
        (ok (get funding-amount proposal)))
      (if (get funded proposal)
        ERR_ALREADY_FUNDED
        (if (not (is-eq (get status proposal) "approved"))
          ERR_PROPOSAL_NOT_APPROVED
          ERR_INSUFFICIENT_FUNDS)))))

(define-read-only (get-proposal (proposal-id uint))
  (map-get? proposals { proposal-id: proposal-id }))

(define-read-only (get-researcher-info (researcher principal))
  (map-get? researchers { researcher: researcher }))

(define-read-only (get-reviewer-info (reviewer principal))
  (map-get? reviewer-status { reviewer: reviewer }))

(define-read-only (get-vote (proposal-id uint) (voter principal))
  (map-get? votes { proposal-id: proposal-id, voter: voter }))

(define-read-only (get-treasury-balance)
  (var-get total-treasury))

(define-read-only (get-total-proposals)
  (var-get proposal-counter))

(define-read-only (is-voting-active (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal (< stacks-block-height (get voting-end-block proposal))
    false))

(define-read-only (get-proposal-status (proposal-id uint))
  (match (map-get? proposals { proposal-id: proposal-id })
    proposal (get status proposal)
    "not-found"))
