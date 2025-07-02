
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

(define-map proposal-milestones
  { proposal-id: uint }
  { 
    total-milestones: uint,
    completed-milestones: uint,
    milestone-funding: uint
  })

(define-map milestones
  { proposal-id: uint, milestone-id: uint }
  {
    description: (string-ascii 200),
    funding-percentage: uint,
    status: (string-ascii 20),
    approvals: uint,
    required-approvals: uint
  })

(define-map milestone-approvals
  { proposal-id: uint, milestone-id: uint, reviewer: principal }
  { approved: bool })

(define-public (create-milestones (proposal-id uint) (milestone-descriptions (list 5 (string-ascii 200))) (funding-percentages (list 5 uint)))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        (milestone-count (len milestone-descriptions)))
    (asserts! (is-eq (get researcher proposal) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (fold + funding-percentages u0) u100) ERR_INVALID_AMOUNT)
    (asserts! (is-eq (get status proposal) "approved") ERR_PROPOSAL_NOT_APPROVED)
    (map-set proposal-milestones
      { proposal-id: proposal-id }
      {
        total-milestones: milestone-count,
        completed-milestones: u0,
        milestone-funding: (get funding-amount proposal)
      })
    (fold create-single-milestone 
          (zip milestone-descriptions funding-percentages)
          { proposal-id: proposal-id, counter: u0 })
    (ok milestone-count)))

(define-private (create-single-milestone (milestone-data { description: (string-ascii 200), percentage: uint }) (acc { proposal-id: uint, counter: uint }))
  (let ((milestone-id (+ (get counter acc) u1)))
    (map-set milestones
      { proposal-id: (get proposal-id acc), milestone-id: milestone-id }
      {
        description: (get description milestone-data),
        funding-percentage: (get percentage milestone-data),
        status: "pending",
        approvals: u0,
        required-approvals: u3
      })
    { proposal-id: (get proposal-id acc), counter: milestone-id }))

(define-private (zip (list-a (list 5 (string-ascii 200))) (list-b (list 5 uint)))
  (map combine-elements list-a list-b))

(define-private (combine-elements (a (string-ascii 200)) (b uint))
  { description: a, percentage: b })

(define-public (approve-milestone (proposal-id uint) (milestone-id uint))
  (let ((milestone (unwrap! (map-get? milestones { proposal-id: proposal-id, milestone-id: milestone-id }) ERR_PROPOSAL_NOT_FOUND))
        (reviewer-info (unwrap! (map-get? reviewer-status { reviewer: tx-sender }) ERR_NOT_AUTHORIZED)))
    (asserts! (get is-reviewer reviewer-info) ERR_NOT_AUTHORIZED)
    (asserts! (is-none (map-get? milestone-approvals { proposal-id: proposal-id, milestone-id: milestone-id, reviewer: tx-sender })) ERR_ALREADY_VOTED)
    (map-set milestone-approvals
      { proposal-id: proposal-id, milestone-id: milestone-id, reviewer: tx-sender }
      { approved: true })
    (let ((new-approvals (+ (get approvals milestone) u1)))
      (map-set milestones
        { proposal-id: proposal-id, milestone-id: milestone-id }
        (merge milestone { approvals: new-approvals }))
      (if (>= new-approvals (get required-approvals milestone))
        (complete-milestone proposal-id milestone-id)
        (ok true)))))

(define-private (complete-milestone (proposal-id uint) (milestone-id uint))
  (let ((milestone (unwrap-panic (map-get? milestones { proposal-id: proposal-id, milestone-id: milestone-id })))
        (proposal-milestones-info (unwrap-panic (map-get? proposal-milestones { proposal-id: proposal-id }))))
    (map-set milestones
      { proposal-id: proposal-id, milestone-id: milestone-id }
      (merge milestone { status: "completed" }))
    (map-set proposal-milestones
      { proposal-id: proposal-id }
      (merge proposal-milestones-info 
        { completed-milestones: (+ (get completed-milestones proposal-milestones-info) u1) }))
    (ok true)))

(define-public (claim-milestone-funding (proposal-id uint) (milestone-id uint))
  (let ((proposal (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        (milestone (unwrap! (map-get? milestones { proposal-id: proposal-id, milestone-id: milestone-id }) ERR_PROPOSAL_NOT_FOUND))
        (proposal-milestones-info (unwrap! (map-get? proposal-milestones { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND)))
    (asserts! (is-eq (get researcher proposal) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status milestone) "completed") ERR_PROPOSAL_NOT_APPROVED)
    (let ((funding-amount (/ (* (get milestone-funding proposal-milestones-info) (get funding-percentage milestone)) u100)))
      (asserts! (>= (var-get total-treasury) funding-amount) ERR_INSUFFICIENT_FUNDS)
      (try! (as-contract (stx-transfer? funding-amount tx-sender (get researcher proposal))))
      (var-set total-treasury (- (var-get total-treasury) funding-amount))
      (map-set milestones
        { proposal-id: proposal-id, milestone-id: milestone-id }
        (merge milestone { status: "funded" }))
      (ok funding-amount))))

(define-read-only (get-milestone (proposal-id uint) (milestone-id uint))
  (map-get? milestones { proposal-id: proposal-id, milestone-id: milestone-id }))

(define-read-only (get-proposal-milestones (proposal-id uint))
  (map-get? proposal-milestones { proposal-id: proposal-id }))