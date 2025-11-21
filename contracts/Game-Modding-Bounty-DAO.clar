(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u401))
(define-constant ERR_BOUNTY_NOT_FOUND (err u404))
(define-constant ERR_INSUFFICIENT_FUNDS (err u402))
(define-constant ERR_ALREADY_VOTED (err u403))
(define-constant ERR_INVALID_AMOUNT (err u400))
(define-constant ERR_BOUNTY_EXPIRED (err u410))
(define-constant ERR_BOUNTY_ACTIVE (err u411))
(define-constant ERR_NOT_MEMBER (err u405))
(define-constant ERR_MILESTONE_NOT_FOUND (err u406))
(define-constant ERR_MILESTONE_COMPLETED (err u407))
(define-constant ERR_INVALID_MILESTONE (err u408))
(define-constant ERR_MILESTONE_NOT_SUBMITTED (err u409))
(define-constant ERR_DISPUTE_NOT_FOUND (err u412))
(define-constant ERR_DISPUTE_ALREADY_EXISTS (err u413))
(define-constant ERR_DISPUTE_CLOSED (err u414))
(define-constant ERR_INSUFFICIENT_REPUTATION (err u415))
(define-constant MIN_BOUNTY_AMOUNT u1000000)
(define-constant VOTING_PERIOD u1008)
(define-constant MIN_VOTES_REQUIRED u3)
(define-constant MAX_MILESTONES u10)
(define-constant DISPUTE_VOTING_PERIOD u504)
(define-constant MIN_DISPUTE_VOTES u5)
(define-constant MIN_REPUTATION_TO_DISPUTE u5)

(define-data-var next-bounty-id uint u1)
(define-data-var dao-treasury uint u0)
(define-data-var total-members uint u0)
(define-data-var next-milestone-bounty-id uint u1)
(define-data-var next-dispute-id uint u1)

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

(define-map milestone-bounties
  { bounty-id: uint }
  {
    creator: principal,
    title: (string-ascii 100),
    description: (string-ascii 500),
    total-reward: uint,
    assignee: principal,
    total-milestones: uint,
    completed-milestones: uint,
    created-at: uint,
    status: (string-ascii 20)
  }
)

(define-map milestones
  { bounty-id: uint, milestone-index: uint }
  {
    description: (string-ascii 300),
    reward-amount: uint,
    deadline: uint,
    status: (string-ascii 20),
    submission-url: (optional (string-ascii 200)),
    submitted-at: (optional uint),
    completed-at: (optional uint)
  }
)

(define-map disputes
  { dispute-id: uint }
  {
    bounty-id: uint,
    disputer: principal,
    reason: (string-ascii 500),
    created-at: uint,
    voting-deadline: uint,
    status: (string-ascii 20),
    votes-for: uint,
    votes-against: uint,
    resolved-at: (optional uint)
  }
)

(define-map dispute-votes
  { dispute-id: uint, voter: principal }
  {
    vote: bool,
    voted-at: uint
  }
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

(define-public (create-milestone-bounty 
  (title (string-ascii 100)) 
  (description (string-ascii 500)) 
  (assignee principal)
  (milestone-descriptions (list 10 (string-ascii 300)))
  (milestone-rewards (list 10 uint))
  (milestone-deadlines (list 10 uint)))
  (let (
    (bounty-id (var-get next-milestone-bounty-id))
    (num-milestones (len milestone-descriptions))
    (total-reward (fold + milestone-rewards u0))
  )
    (asserts! (is-some (map-get? member-registry { member: tx-sender })) ERR_NOT_MEMBER)
    (asserts! (is-some (map-get? member-registry { member: assignee })) ERR_NOT_MEMBER)
    (asserts! (and (> num-milestones u0) (<= num-milestones MAX_MILESTONES)) ERR_INVALID_MILESTONE)
    (asserts! (is-eq num-milestones (len milestone-rewards)) ERR_INVALID_MILESTONE)
    (asserts! (is-eq num-milestones (len milestone-deadlines)) ERR_INVALID_MILESTONE)
    (asserts! (>= total-reward MIN_BOUNTY_AMOUNT) ERR_INVALID_AMOUNT)
    (asserts! (>= (var-get dao-treasury) total-reward) ERR_INSUFFICIENT_FUNDS)
    
    (map-set milestone-bounties
      { bounty-id: bounty-id }
      {
        creator: tx-sender,
        title: title,
        description: description,
        total-reward: total-reward,
        assignee: assignee,
        total-milestones: num-milestones,
        completed-milestones: u0,
        created-at: stacks-block-height,
        status: "active"
      }
    )
    
    (map create-milestone-entry 
      milestone-descriptions 
      milestone-rewards 
      milestone-deadlines 
      (list bounty-id bounty-id bounty-id bounty-id bounty-id bounty-id bounty-id bounty-id bounty-id bounty-id)
      (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9))
    
    (var-set next-milestone-bounty-id (+ bounty-id u1))
    (var-set dao-treasury (- (var-get dao-treasury) total-reward))
    (ok bounty-id)
  )
)

(define-private (create-milestone-entry 
  (desc (string-ascii 300)) 
  (reward uint) 
  (deadline uint) 
  (bounty-id uint) 
  (index uint))
  (begin
    (map-set milestones
      { bounty-id: bounty-id, milestone-index: index }
      {
        description: desc,
        reward-amount: reward,
        deadline: deadline,
        status: "pending",
        submission-url: none,
        submitted-at: none,
        completed-at: none
      }
    )
    true
  )
)

(define-public (submit-milestone-completion (bounty-id uint) (milestone-index uint) (submission-url (string-ascii 200)))
  (let (
    (bounty-data (map-get? milestone-bounties { bounty-id: bounty-id }))
    (milestone-data (map-get? milestones { bounty-id: bounty-id, milestone-index: milestone-index }))
  )
    (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (is-some milestone-data) ERR_MILESTONE_NOT_FOUND)
    (let (
      (bounty (unwrap-panic bounty-data))
      (milestone (unwrap-panic milestone-data))
    )
      (asserts! (is-eq tx-sender (get assignee bounty)) ERR_NOT_AUTHORIZED)
      (asserts! (is-eq (get status milestone) "pending") ERR_MILESTONE_COMPLETED)
      (asserts! (is-eq (get status bounty) "active") ERR_BOUNTY_ACTIVE)
      
      (map-set milestones
        { bounty-id: bounty-id, milestone-index: milestone-index }
        {
          description: (get description milestone),
          reward-amount: (get reward-amount milestone),
          deadline: (get deadline milestone),
          status: "submitted",
          submission-url: (some submission-url),
          submitted-at: (some stacks-block-height),
          completed-at: none
        }
      )
      (ok "Milestone submitted for review")
    )
  )
)

(define-public (approve-milestone (bounty-id uint) (milestone-index uint))
  (let (
    (bounty-data (map-get? milestone-bounties { bounty-id: bounty-id }))
    (milestone-data (map-get? milestones { bounty-id: bounty-id, milestone-index: milestone-index }))
  )
    (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (is-some milestone-data) ERR_MILESTONE_NOT_FOUND)
    (let (
      (bounty (unwrap-panic bounty-data))
      (milestone (unwrap-panic milestone-data))
    )
      (asserts! (is-eq tx-sender (get creator bounty)) ERR_NOT_AUTHORIZED)
      (asserts! (is-eq (get status milestone) "submitted") ERR_MILESTONE_NOT_SUBMITTED)
      (asserts! (is-eq (get status bounty) "active") ERR_BOUNTY_ACTIVE)
      
      (try! (as-contract (stx-transfer? (get reward-amount milestone) tx-sender (get assignee bounty))))
      
      (map-set milestones
        { bounty-id: bounty-id, milestone-index: milestone-index }
        {
          description: (get description milestone),
          reward-amount: (get reward-amount milestone),
          deadline: (get deadline milestone),
          status: "completed",
          submission-url: (get submission-url milestone),
          submitted-at: (get submitted-at milestone),
          completed-at: (some stacks-block-height)
        }
      )
      
      (let ((new-completed (+ (get completed-milestones bounty) u1)))
        (map-set milestone-bounties
          { bounty-id: bounty-id }
          {
            creator: (get creator bounty),
            title: (get title bounty),
            description: (get description bounty),
            total-reward: (get total-reward bounty),
            assignee: (get assignee bounty),
            total-milestones: (get total-milestones bounty),
            completed-milestones: new-completed,
            created-at: (get created-at bounty),
            status: (if (is-eq new-completed (get total-milestones bounty)) "completed" "active")
          }
        )
        
        (if (is-eq new-completed (get total-milestones bounty))
          (let ((assignee-data (unwrap-panic (map-get? member-registry { member: (get assignee bounty) }))))
            (map-set member-registry
              { member: (get assignee bounty) }
              {
                joined-at: (get joined-at assignee-data),
                reputation-score: (+ (get reputation-score assignee-data) (* u5 (get total-milestones bounty))),
                total-submissions: (get total-submissions assignee-data),
                total-rewards: (+ (get total-rewards assignee-data) (get total-reward bounty))
              }
            )
          )
          true
        )
      )
      (ok "Milestone approved and payment released")
    )
  )
)

(define-read-only (get-milestone-bounty (bounty-id uint))
  (map-get? milestone-bounties { bounty-id: bounty-id })
)

(define-read-only (get-milestone-info (bounty-id uint) (milestone-index uint))
  (map-get? milestones { bounty-id: bounty-id, milestone-index: milestone-index })
)

(define-read-only (get-milestone-progress (bounty-id uint))
  (let ((bounty-data (map-get? milestone-bounties { bounty-id: bounty-id })))
    (if (is-some bounty-data)
      (let ((bounty (unwrap-panic bounty-data)))
        (ok {
          completed: (get completed-milestones bounty),
          total: (get total-milestones bounty),
          status: (get status bounty)
        })
      )
      ERR_BOUNTY_NOT_FOUND
    )
  )
)

(define-public (create-dispute (bounty-id uint) (reason (string-ascii 500)))
  (let (
    (dispute-id (var-get next-dispute-id))
    (bounty-data (map-get? bounties { bounty-id: bounty-id }))
    (member-data (map-get? member-registry { member: tx-sender }))
    (submission-data (map-get? bounty-submissions { bounty-id: bounty-id, submitter: tx-sender }))
    (existing-dispute-check (fold check-existing-dispute 
      (list u1 u2 u3 u4 u5 u6 u7 u8 u9 u10)
      { bounty: bounty-id, sender: tx-sender, found: false }))
  )
    (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (is-some member-data) ERR_NOT_MEMBER)
    (asserts! (is-some submission-data) ERR_BOUNTY_NOT_FOUND)
    (asserts! (>= (get reputation-score (unwrap-panic member-data)) MIN_REPUTATION_TO_DISPUTE) ERR_INSUFFICIENT_REPUTATION)
    (asserts! (not (get found existing-dispute-check)) ERR_DISPUTE_ALREADY_EXISTS)
    
    (let ((bounty (unwrap-panic bounty-data)))
      (asserts! (is-eq (get status bounty) "completed") ERR_BOUNTY_ACTIVE)
      (asserts! (not (is-eq (some tx-sender) (get winner bounty))) ERR_NOT_AUTHORIZED)
      
      (map-set disputes
        { dispute-id: dispute-id }
        {
          bounty-id: bounty-id,
          disputer: tx-sender,
          reason: reason,
          created-at: stacks-block-height,
          voting-deadline: (+ stacks-block-height DISPUTE_VOTING_PERIOD),
          status: "active",
          votes-for: u0,
          votes-against: u0,
          resolved-at: none
        }
      )
      (var-set next-dispute-id (+ dispute-id u1))
      (ok dispute-id)
    )
  )
)

(define-private (check-existing-dispute (id uint) (acc { bounty: uint, sender: principal, found: bool }))
  (if (get found acc)
    acc
    (let ((dispute-data (map-get? disputes { dispute-id: id })))
      (if (is-some dispute-data)
        (let ((dispute (unwrap-panic dispute-data)))
          (if (and 
                (is-eq (get bounty-id dispute) (get bounty acc))
                (is-eq (get disputer dispute) (get sender acc))
                (or (is-eq (get status dispute) "active") (is-eq (get status dispute) "pending")))
            { bounty: (get bounty acc), sender: (get sender acc), found: true }
            acc
          )
        )
        acc
      )
    )
  )
)

(define-public (vote-on-dispute (dispute-id uint) (vote-for bool))
  (let (
    (dispute-data (map-get? disputes { dispute-id: dispute-id }))
    (member-data (map-get? member-registry { member: tx-sender }))
    (existing-vote (map-get? dispute-votes { dispute-id: dispute-id, voter: tx-sender }))
  )
    (asserts! (is-some dispute-data) ERR_DISPUTE_NOT_FOUND)
    (asserts! (is-some member-data) ERR_NOT_MEMBER)
    (asserts! (is-none existing-vote) ERR_ALREADY_VOTED)
    
    (let ((dispute (unwrap-panic dispute-data)))
      (asserts! (is-eq (get status dispute) "active") ERR_DISPUTE_CLOSED)
      (asserts! (< stacks-block-height (get voting-deadline dispute)) ERR_BOUNTY_EXPIRED)
      
      (map-set dispute-votes
        { dispute-id: dispute-id, voter: tx-sender }
        {
          vote: vote-for,
          voted-at: stacks-block-height
        }
      )
      
      (map-set disputes
        { dispute-id: dispute-id }
        {
          bounty-id: (get bounty-id dispute),
          disputer: (get disputer dispute),
          reason: (get reason dispute),
          created-at: (get created-at dispute),
          voting-deadline: (get voting-deadline dispute),
          status: (get status dispute),
          votes-for: (if vote-for (+ (get votes-for dispute) u1) (get votes-for dispute)),
          votes-against: (if vote-for (get votes-against dispute) (+ (get votes-against dispute) u1)),
          resolved-at: (get resolved-at dispute)
        }
      )
      (ok "Vote recorded")
    )
  )
)

(define-public (resolve-dispute (dispute-id uint))
  (let ((dispute-data (map-get? disputes { dispute-id: dispute-id })))
    (asserts! (is-some dispute-data) ERR_DISPUTE_NOT_FOUND)
    
    (let ((dispute (unwrap-panic dispute-data)))
      (asserts! (is-eq (get status dispute) "active") ERR_DISPUTE_CLOSED)
      (asserts! (>= stacks-block-height (get voting-deadline dispute)) ERR_BOUNTY_ACTIVE)
      
      (let (
        (total-votes (+ (get votes-for dispute) (get votes-against dispute)))
        (dispute-approved (and (>= total-votes MIN_DISPUTE_VOTES) (> (get votes-for dispute) (get votes-against dispute))))
        (bounty-data (map-get? bounties { bounty-id: (get bounty-id dispute) }))
      )
        (asserts! (is-some bounty-data) ERR_BOUNTY_NOT_FOUND)
        
        (if dispute-approved
          (let ((bounty (unwrap-panic bounty-data)))
            (let ((old-winner (unwrap-panic (get winner bounty))))
              (try! (as-contract (stx-transfer? (get reward-amount bounty) old-winner (get disputer dispute))))
              
              (map-set bounties
                { bounty-id: (get bounty-id dispute) }
                {
                  creator: (get creator bounty),
                  title: (get title bounty),
                  description: (get description bounty),
                  reward-amount: (get reward-amount bounty),
                  deadline: (get deadline bounty),
                  status: "completed",
                  winner: (some (get disputer dispute)),
                  total-votes: (get total-votes bounty),
                  created-at: (get created-at bounty)
                }
              )
              
              (let ((old-winner-data (unwrap-panic (map-get? member-registry { member: old-winner }))))
                (map-set member-registry
                  { member: old-winner }
                  {
                    joined-at: (get joined-at old-winner-data),
                    reputation-score: (if (>= (get reputation-score old-winner-data) u10) 
                                        (- (get reputation-score old-winner-data) u10) 
                                        u0),
                    total-submissions: (get total-submissions old-winner-data),
                    total-rewards: (- (get total-rewards old-winner-data) (get reward-amount bounty))
                  }
                )
              )
              
              (let ((disputer-data (unwrap-panic (map-get? member-registry { member: (get disputer dispute) }))))
                (map-set member-registry
                  { member: (get disputer dispute) }
                  {
                    joined-at: (get joined-at disputer-data),
                    reputation-score: (+ (get reputation-score disputer-data) u15),
                    total-submissions: (get total-submissions disputer-data),
                    total-rewards: (+ (get total-rewards disputer-data) (get reward-amount bounty))
                  }
                )
              )
            )
          )
          true
        )
        
        (map-set disputes
          { dispute-id: dispute-id }
          {
            bounty-id: (get bounty-id dispute),
            disputer: (get disputer dispute),
            reason: (get reason dispute),
            created-at: (get created-at dispute),
            voting-deadline: (get voting-deadline dispute),
            status: (if dispute-approved "approved" "rejected"),
            votes-for: (get votes-for dispute),
            votes-against: (get votes-against dispute),
            resolved-at: (some stacks-block-height)
          }
        )
        
        (ok dispute-approved)
      )
    )
  )
)

(define-read-only (get-dispute (dispute-id uint))
  (map-get? disputes { dispute-id: dispute-id })
)

(define-read-only (get-dispute-vote (dispute-id uint) (voter principal))
  (map-get? dispute-votes { dispute-id: dispute-id, voter: voter })
)

(define-read-only (has-voted-on-dispute (dispute-id uint) (voter principal))
  (is-some (map-get? dispute-votes { dispute-id: dispute-id, voter: voter }))
)
