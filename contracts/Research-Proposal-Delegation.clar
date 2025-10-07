(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u101))
(define-constant ERR_VOTING_ENDED (err u103))
(define-constant ERR_SELF_DELEGATION (err u301))
(define-constant ERR_NO_DELEGATION (err u303))

(define-map delegations
  { delegator: principal }
  { delegate: principal, active: bool })

(define-map delegation-votes
  { proposal-id: uint, delegator: principal }
  { delegate: principal, vote: bool })

(define-public (delegate-voting-power (delegate principal))
  (let ((reviewer-info (unwrap! (contract-call? .Decentralized-Research get-reviewer-info tx-sender) ERR_NOT_AUTHORIZED)))
    (asserts! (get is-reviewer reviewer-info) ERR_NOT_AUTHORIZED)
    (asserts! (not (is-eq delegate tx-sender)) ERR_SELF_DELEGATION)
    (map-set delegations
      { delegator: tx-sender }
      { delegate: delegate, active: true })
    (ok delegate)))

(define-public (revoke-delegation)
  (let ((delegation (unwrap! (map-get? delegations { delegator: tx-sender }) ERR_NO_DELEGATION)))
    (map-set delegations
      { delegator: tx-sender }
      (merge delegation { active: false }))
    (ok true)))

(define-public (vote-as-delegate (proposal-id uint) (vote-for bool) (delegator principal))
  (let ((proposal (unwrap! (contract-call? .Decentralized-Research get-proposal proposal-id) ERR_PROPOSAL_NOT_FOUND))
        (delegation (unwrap! (map-get? delegations { delegator: delegator }) ERR_NO_DELEGATION)))
    (asserts! (is-eq (get delegate delegation) tx-sender) ERR_NOT_AUTHORIZED)
    (asserts! (get active delegation) ERR_NO_DELEGATION)
    (asserts! (< stacks-block-height (get voting-end-block proposal)) ERR_VOTING_ENDED)
    (map-set delegation-votes
      { proposal-id: proposal-id, delegator: delegator }
      { delegate: tx-sender, vote: vote-for })
    (ok true)))

(define-read-only (get-delegation (delegator principal))
  (map-get? delegations { delegator: delegator }))

(define-read-only (get-delegation-vote (proposal-id uint) (delegator principal))
  (map-get? delegation-votes { proposal-id: proposal-id, delegator: delegator }))

(define-read-only (is-delegated-to (delegator principal) (delegate principal))
  (match (map-get? delegations { delegator: delegator })
    delegation (and (is-eq (get delegate delegation) delegate) (get active delegation))
    false))

(define-read-only (count-delegators (delegate principal))
  (ok u0))
