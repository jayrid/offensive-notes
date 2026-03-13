The full pipeline starts with the planner (to generate mission_plan.json and  
  register in the index), then hands off to master for execution:               
                                                                                
  Step 1 — Plan the mission:
  use @redteam-mission-planner target:dvwa ip:10.10.30.128                      
                                                                  
  Step 2 — Execute the mission:
  use @redteam-master target:dvwa ip:10.10.30.128

  Master will automatically load mission_plan.json, enforce its constraints, and
   delegate each phase to the appropriate sub-agents in order:
  @redteam-recon → @redteam-scan → @redteam-enum → @redteam-exploit-specialist →
   @redteam-postex-specialist → @redteam-report-writer

  To resume an interrupted mission:
  use @redteam-master target:dvwa ip:10.10.30.128 resume

  Replace dvwa with your target type (bwapp, metasploitable, hackthebox, etc.)
  and the IP with your actual target.
