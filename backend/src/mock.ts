/**
 * Lets the built-in demo agent trigger realistic approval requests from chat,
 * so you can test the whole approve/decline flow from the watch without writing any agent code.
 */
export function demoApprovalFor(text: string): Record<string, unknown> | undefined {
  const t = text.toLowerCase();
  if (/\bemail\b/.test(t)) {
    return {
      action_type: "send_email",
      title: "Send email to Sam",
      risk: "low",
      details: { To: "sam@example.com", Subject: "Notes from today's meeting", Attachments: "none" },
      reasoning: "You asked me to email Sam. I drafted a short summary of today's meeting notes.",
    };
  }
  if (/\b(run|command|deploy)\b/.test(t)) {
    return {
      action_type: "run_command",
      title: "Run build script",
      risk: "medium",
      details: { Command: "npm run build && npm run deploy", Directory: "~/projects/site", Host: "my-laptop" },
      reasoning: "Deploying is the last step of the task you gave me. This runs on your laptop.",
    };
  }
  if (/\b(buy|purchase|order)\b/.test(t)) {
    return {
      action_type: "purchase",
      title: "Buy USB-C cable",
      risk: "high",
      details: { Merchant: "Example Store", Amount: "$24.99", "Card ending": "4242" },
      reasoning: "You asked me to order a replacement USB-C cable. This was the cheapest 2 m option in stock.",
    };
  }
  if (/\bpush\b/.test(t)) {
    return {
      action_type: "code_push",
      title: "Push 3 commits to main",
      risk: "high",
      details: { Repository: "example/site", Branch: "main", Commits: "3" },
      reasoning: "The tests pass locally and you asked me to ship the fix.",
    };
  }
  return undefined;
}
