import Foundation

private func testQuotaCreditWeighting() {
    let tokens = TokenBreakdown(input: 2_000_000, cachedInput: 1_800_000, output: 10_000, reasoning: 5_000, total: 2_015_000)
    let sol = QuotaCreditWeighting.credits(for: tokens, model: "gpt-5.6-sol")
    let terra = QuotaCreditWeighting.credits(for: tokens, model: "gpt-5.6-terra")
    precondition(abs(sol - 45.5) < 0.0001)
    precondition(abs(terra - 23.5) < 0.0001)
    precondition(QuotaCreditWeighting.rates(for: "gpt-5.6-sol").cachedInput == 10)
    // Account totals may include a heavy task from another device. It expands
    // the denominator instead of being assigned to this device's local turn.
    let crossDevice = QuotaCreditWeighting.accountCoveredCredits(localCredits: sol, localTokens: 2_015_000, accountTokens: 20_150_000)
    precondition(abs(crossDevice - 455) < 0.0001)
}

@main
enum SessionUsageScannerTests {
    static func main() {
        testQuotaCreditWeighting()
        let fixture = """
        {"timestamp":"2026-08-25T08:00:00.000Z","type":"session_meta","payload":{"id":"thread-1"}}
        {"timestamp":"2026-08-25T08:01:00.000Z","type":"event_msg","payload":{"type":"task_started","turn_id":"turn-native-1"}}
        {"timestamp":"2026-08-25T08:01:01.000Z","type":"turn_context","payload":{"model":"gpt-test","effort":"high"}}
        {"timestamp":"2026-08-25T08:01:02.000Z","type":"response_item","payload":{"type":"custom_tool_call"}}
        {"timestamp":"2026-08-25T08:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":700,"output_tokens":80,"reasoning_output_tokens":20,"total_tokens":1100}}}}
        {"timestamp":"2026-08-25T08:01:10.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":2400,"cached_input_tokens":1500,"output_tokens":160,"reasoning_output_tokens":40,"total_tokens":2600}}}}
        {"timestamp":"2026-08-25T08:01:11.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """

        let turns = SessionUsageScanner().parse(data: Data(fixture.utf8))

        precondition(turns.count == 1)
        precondition(turns[0].threadID == "thread-1")
        precondition(turns[0].turnID == "turn-native-1")
        precondition(turns[0].tokens.total == 2600)
        precondition(turns[0].tokens.uncachedInput == 900)
        precondition(turns[0].toolCallCount == 1)
        precondition(turns[0].model == "gpt-test")
        precondition(turns[0].reasoningEffort == "high")
        precondition(turns[0].ordinal == 1)

        let incrementalFixture = """
        {"timestamp":"2026-08-25T09:00:00.000Z","type":"session_meta","payload":{"id":"thread-2","cwd":"/tmp/codex-meter"}}
        {"timestamp":"2026-08-25T09:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-08-25T09:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":9000,"cached_input_tokens":7000,"output_tokens":800,"reasoning_output_tokens":200,"total_tokens":10000},"last_token_usage":{"input_tokens":900,"cached_input_tokens":700,"output_tokens":80,"reasoning_output_tokens":20,"total_tokens":1000}}}}
        {"timestamp":"2026-08-25T09:01:07.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":10800,"cached_input_tokens":8400,"output_tokens":960,"reasoning_output_tokens":240,"total_tokens":12000},"last_token_usage":{"input_tokens":1800,"cached_input_tokens":1400,"output_tokens":160,"reasoning_output_tokens":40,"total_tokens":2000}}}}
        {"timestamp":"2026-08-25T09:01:08.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        let incrementalTurns = SessionUsageScanner().parse(data: Data(incrementalFixture.utf8))
        precondition(incrementalTurns.count == 1)
        precondition(incrementalTurns[0].tokens.total == 3000)
        precondition(incrementalTurns[0].tokens.cachedInput == 2100)
        precondition(incrementalTurns[0].workspaceName == "codex-meter")

        let titledFixture = """
        {"timestamp":"2026-08-25T10:00:00.000Z","type":"session_meta","payload":{"id":"thread-3"}}
        {"timestamp":"2026-08-25T10:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-08-25T10:01:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"## My request:\\n帮我精简最近一轮消耗卡片。还要调整历史入口。"}]}}
        {"timestamp":"2026-08-25T10:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}}
        {"timestamp":"2026-08-25T10:01:04.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        let titledTurns = SessionUsageScanner().parse(data: Data(titledFixture.utf8))
        precondition(titledTurns[0].threadTitle == "帮我精简最近一轮消耗卡…", "title=\(titledTurns[0].threadTitle ?? "nil")")
        let privateTurns = SessionUsageScanner().parse(data: Data(titledFixture.utf8), includePromptTitles: false)
        precondition(privateTurns[0].threadTitle == nil)
        precondition(PromptTitleFormatter.title(from: "「最近一次消耗」这部分感觉还是有点太复杂了，不够精简干净") == "「最近一次消耗」这部分…")
        precondition(PromptTitleFormatter.title(from: "请看这个问题 <image name=\"shot\">ignored</image> 然后修复菜单栏") == "请看这个问题 然后修复…")
        precondition(PromptTitleFormatter.title(from: "<image name=\"shot\">ignored</image>") == "图片对话")
        precondition(PromptTitleFormatter.title(from: "</image>") == "图片对话")
        precondition(PromptTitleFormatter.title(from: "<environment_context>\\n<cwd>/tmp/project</cwd>\\n</environment_context>") == nil)
        precondition(PromptTitleFormatter.title(from: "<recommended_plugins>\\n- Figma\\n</recommended_plugins>") == nil)

        let injectedContextFixture = """
        {"timestamp":"2026-08-25T10:30:00.000Z","type":"session_meta","payload":{"id":"thread-injected"}}
        {"timestamp":"2026-08-25T10:31:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-08-25T10:31:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"<recommended_plugins>\\n- Figma\\n</recommended_plugins>"},{"type":"input_text","text":"<environment_context>\\n<cwd>/tmp/project</cwd>\\n</environment_context>"}]}}
        {"timestamp":"2026-08-25T10:31:02.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"查一下 bug，为什么标题显示成代码了？"}]}}
        {"timestamp":"2026-08-25T10:31:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}}
        {"timestamp":"2026-08-25T10:31:04.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        let injectedContextTurns = SessionUsageScanner().parse(data: Data(injectedContextFixture.utf8))
        precondition(injectedContextTurns[0].threadTitle == "查一下 bug，为什么…", "title=\(injectedContextTurns[0].threadTitle ?? "nil")")

        let imageOnlyFixture = """
        {"timestamp":"2026-08-25T11:00:00.000Z","type":"session_meta","payload":{"id":"thread-image"}}
        {"timestamp":"2026-08-25T11:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-08-25T11:01:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"local_image","path":"/tmp/shot.png"}]}}
        {"timestamp":"2026-08-25T11:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":20,"reasoning_output_tokens":0,"total_tokens":120}}}}
        {"timestamp":"2026-08-25T11:01:04.000Z","type":"event_msg","payload":{"type":"task_complete"}}
        """
        precondition(SessionUsageScanner().parse(data: Data(imageOnlyFixture.utf8))[0].threadTitle == "图片对话")

        let incompleteFixture = """
        {"timestamp":"2026-08-25T08:01:00.000Z","type":"event_msg","payload":{"type":"task_started"}}
        {"timestamp":"2026-08-25T08:01:03.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":700,"output_tokens":80,"reasoning_output_tokens":20,"total_tokens":1100}}}}
        """

        precondition(SessionUsageScanner().parse(data: Data(incompleteFixture.utf8)).isEmpty)
        print("SessionUsageScanner self-test passed")
    }
}
