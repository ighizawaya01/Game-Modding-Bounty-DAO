(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_BOUNTY_NOT_FOUND (err u404))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_ALREADY_VOTED (err u403))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_BOUNTY_EXPIRED (err u410))
(define-constant ERR_BOUNTY_ACTIVE (err u411))
(define-constant ERR_NOT_MEMBER (err u405))
(define-constant MIN_BOUNTY_AMOUNT u1000000)
(define-constant VOTING_PERIOD u1008)
(define-constant MIN_VOTES_REQUIRED u3)

(define-data-var next-bounty-id uint u1)
(define-data-var dao-treasury uint u0)
(define-data-var total-members uint u0)

(define-map bounties
  { bounty-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    reward-amount: uint,
    deadline: uint,
    status: (string-ascii 20),
    winner: (optional principal),
    total-votes: uint,
    created-at: uint
  }
)

(define-map member-registry
  { member: principal }
  {
    joined-at: uint,
    reputation-score: uint,
    total-submissions: uint,
    total-rewards: uint
  }
)

(define-map bounty-submissions
  { bounty-id: uint, submitter: principal }
  {
    mod-url: (string-ascii 200),
    description: (string-ascii 300),
    submitted-at: uint,
    vote-count: uint
  }
)

(define-map bounty-votes
  { bounty-id: uint, voter: principal, submitter: principal }
  { voted-at: uint }
)

(define-map treasury-contributions
  { contributor: principal }
  { total-contributed: uint, last-contribution: uint }
)

(define-public (join-dao)
  (let ((member-data (map-get? member-registry { member: tx-sender })))
    (if (is-none member-data)
      (begin
        (map-set member-registry
          { member: tx-sender }
          {
            joined-at: stacks-block-height,
            reputation-score: u0,
            total-submissions: u0,
            total-rewards: u0
          }
        )
        (var-set total-members (+ (var-get total-members) u1))
        (ok "Successfully joined DAO")
      )
      (ok "Already a member")
    )
  )
)

(define-public (contribute-to-treasury (amount uint))
  (let ((current-contribution (default-to { total-contributed: u0, last-contribution: u0 }
                                          (map-get? treasury-contributions { contributor: tx-sender }))))
    (if (>= amount u100000)
      (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set dao-treasury (+ (var-get dao-treasury) amount))
        (map-set treasury-contributions
          { contributor: tx-sender }
          {
            total-contributed: (+ (get total-contributed current-contribution) amount),
            last-contribution: stacks-block-height
          }
        )
        (ok amount)
      )
      ERR_INVALID_AMOUNT
    )
  )
)

(define-public (create-bounty (title (string-ascii 100)) (description (string-ascii 500)) (reward-amount uint))
  (let (
    (bounty-id (var-get next-bounty-id))
    (deadline (+ stacks-block-height VOTING_PERIOD))
  )
    (asserts! (>= reward-amount MIN_BOUNTY_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get dao-treasury) reward-amount) ERR_INSUFFICIENT_FUNDS)
    (asserts! (is-some (map-get? member-registry { member: tx-sender })) ERR_NOT_MEMBER)
    
    (map-set bounties
      { bounty-id: bounty-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        reward-amount: reward-amount,
        deadline: deadline,
        status: "active",
        winner: none,
        total-votes: u0,
        created-at: stacks-block-height
      }
    )
    (var-set next-bounty-id (+ bounty-id u1))
    (var-set dao-treasury (- (var-get dao-treasury) reward-amount))
    (ok bounty-id)
  )
)

(define-public (submit-mod (bounty-id uint) (mod-url (string-ascii 200)) (description (string-ascii 300)))
  (let ((bounty-data (map-get? bounties { bounty-id: bounty-id })))
    (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (is-some (map-get? member-registry { member: tx-sender })) ERR_NOT_MEMBER)
    (asserts! (< stacks-block-height (get deadline (unwrap-panic bounty-data))) ERR_BOUNTY_EXPIRED)
    (asserts! (is-eq (get status (unwrap-panic bounty-data)) "active") ERR_BOUNTY_ACTIVE)
    
    (map-set bounty-submissions
      { bounty-id: bounty-id, submitter: tx-sender }
      {
        mod-url: mod-url,
        description: description,
        submitted-at: stacks-block-height,
        vote-count: u0
      }
    )
    
    (let ((member-data (unwrap-panic (map-get? member-registry { member: tx-sender }))))
      (map-set member-registry
        { member: tx-sender }
        {
          joined-at: (get joined-at member-data),
          reputation-score: (get reputation-score member-data),
          total-submissions: (+ (get total-submissions member-data) u1),
          total-rewards: (get total-rewards member-data)
        }
      )
    )
    (ok "Mod submitted successfully")
  )
)

(define-public (vote-for-submission (bounty-id uint) (submitter principal))
  (let (
    (bounty-data (map-get? bounties { bounty-id: bounty-id }))
    (existing-vote (map-get? bounty-votes { bounty-id: bounty-id, voter: tx-sender, submitter: submitter }))
    (submission-data (map-get? bounty-submissions { bounty-id: bounty-id, submitter: submitter }))
  )
    (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (is-some submission-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    (asserts! (is-some (map-get? member-registry { member: tx-sender })) ERR_NOT_MEMBER)
    (asserts! (< stacks-block-height (get deadline (unwrap-panic bounty-data))) ERR_BOUNTY_EXPIRED)
    
    (map-set bounty-votes
      { bounty-id: bounty-id, voter: tx-sender, submitter: submitter }
      { voted-at: stacks-block-height }
    )
    
    (let ((current-submission (unwrap-panic submission-data)))
      (map-set bounty-submissions
        { bounty-id: bounty-id, submitter: submitter }
        {
          mod-url: (get mod-url current-submission),
          description: (get description current-submission),
          submitted-at: (get submitted-at current-submission),
          vote-count: (+ (get vote-count current-submission) u1)
        }
      )
    )
    
    (let ((current-bounty (unwrap-panic bounty-data)))
      (map-set bounties
        { bounty-id: bounty-id }
        {
          creator: (get creator current-bounty),
          title: (get title current-bounty),
          description: (get description current-bounty),
          reward-amount: (get reward-amount current-bounty),
          deadline: (get deadline current-bounty),
          status: (get status current-bounty),
          winner: (get winner current-bounty),
          total-votes: (+ (get total-votes current-bounty) u1),
          created-at: (get created-at current-bounty)
        }
      )
    )
    (ok "Vote recorded successfully")
  )
)

(define-public (finalize-bounty (bounty-id uint) (winner principal))
  (let ((bounty-data (map-get? bounties { bounty-id: bounty-id })))
    (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
    (let ((bounty (unwrap-panic bounty-data)))
      (asserts! (or (is-eq tx-sender (get creator bounty)) (is-eq tx-sender CONTRACT_OWNER)) ERR_NOT_AUTHORIZED)
      (asserts! (>= stacks-block-height (get deadline bounty)) ERR_BOUNTY_ACTIVE)
      (asserts! (>= (get total-votes bounty) MIN_VOTES_REQUIRED) ERR_INSUFFICIENT_FUNDS)
      (asserts! (is-eq (get status bounty) "active") ERR_BOUNTY_ACTIVE)
      
      (try! (as-contract (stx-transfer? (get reward-amount bounty) tx-sender winner)))
      
      (map-set bounties
        { bounty-id: bounty-id }
        {
          creator: (get creator bounty),
          title: (get title bounty),
          description: (get description bounty),
          reward-amount: (get reward-amount bounty),
          deadline: (get deadline bounty),
          status: "completed",
          winner: (some winner),
          total-votes: (get total-votes bounty),
          created-at: (get created-at bounty)
        }
      )
      
      (let ((winner-data (unwrap-panic (map-get? member-registry { member: winner }))))
        (map-set member-registry
          { member: winner }
          {
            joined-at: (get joined-at winner-data),
            reputation-score: (+ (get reputation-score winner-data) u10),
            total-submissions: (get total-submissions winner-data),
            total-rewards: (+ (get total-rewards winner-data) (get reward-amount bounty))
          }
        )
      )
      (ok winner)
    )
  )
)

(define-read-only (get-bounty (bounty-id uint))
  (map-get? bounties { bounty-id: bounty-id })
)

(define-read-only (get-member-info (member principal))
  (map-get? member-registry { member: member })
)

(define-read-only (get-submission (bounty-id uint) (submitter principal))
  (map-get? bounty-submissions { bounty-id: bounty-id, submitter: submitter })
)

(define-read-only (get-dao-stats)
  {
    total-bounties: (- (var-get next-bounty-id) u1),
    treasury-balance: (var-get dao-treasury),
    total-members: (var-get total-members)
  }
)

(define-read-only (get-contribution-info (contributor principal))
  (map-get? treasury-contributions { contributor: contributor })
)

(define-read-only (has-voted (bounty-id uint) (voter principal) (submitter principal))
  (is-some (map-get? bounty-votes { bounty-id: bounty-id, voter: voter, submitter: submitter }))
)
