import Foundation
import VoiceyCore
@MainActor func smartAgentChecks() async throws {
 let request="Go and ChatGPT and search for top, search for the last five prime ministers of India."
 let goal=try unwrapGoal(request)
 expectEqual(goal.text,"the last five prime ministers of India.");expectTrue(goal.submit)
 expectEqual(try unwrapGoal("Go to ChatGPT and search for the last five prime ministers of India").text,"the last five prime ministers of India")
 expectEqual(try unwrapGoal("Search ChatGPT for the last five prime ministers of India").text,"the last five prime ministers of India")
 expectEqual(try unwrapGoal("Open Chat GPT in Arc and ask it who was the first prime minister of India?").browser,"Arc")
 expectEqual(try unwrapGoal("Ask ChatGPT what is 2 + 2? in Chrome").browser,"Chrome")
 expectEqual(try unwrapGoal("Open ChatGPT and type Hello without submitting").text,"Hello")
 expectFalse(try unwrapGoal("Open ChatGPT and type Hello without submitting").submit)
 expectFalse(try unwrapGoal("Open ChatGPT and search for cats, don't send it yet").submit)
 expectNil(ChatGPTGoal.parse("Search Google for India"));expectNil(ChatGPTGoal.parse("Open ChatGPT"))
 expectEqual(try unwrapGoal("Ask ChatGPT compare India, search for economic data").text,"compare India, search for economic data") // not a search correction
 var w=goal;w.browser="Arc"
 let plan=try WorkflowPlanner.plan(w,original:request)
 expectEqual(plan.steps.map(\.operation),[.launchApplication,.navigate,.inspectPage,.fillPrompt,.submitPrompt])
 expectEqual(plan.steps.last?.arguments.text,goal.text)
 expectEqual(ActionRiskPolicy.evaluate(plan.steps[1],request:request,preview:false),.execute)
 expectEqual(ActionRiskPolicy.evaluate(plan.steps.last!,request:request,preview:false),.execute)
 if case .confirm=ActionRiskPolicy.evaluate(plan.steps.last!,request:request,preview:true){}else{fail("Prompt preview preference bypassed")}
 var changed=plan.steps.last!;changed.arguments.text="the next five prime ministers of India"
 if case .confirm=ActionRiskPolicy.evaluate(changed,request:request,preview:false){}else{fail("Altered prompt bypassed review")}
 changed.arguments.text="my bank account number"
 if case .confirm=ActionRiskPolicy.evaluate(changed,request:"Ask ChatGPT my bank account number",preview:false){}else{fail("Sensitive prompt bypassed review")}
 let mock=MockComputerAdapter(),agent=ComputerUseAgent();agent.register(mock)
 await agent.start(plan)
 expectEqual(agent.task?.status,.complete);expectEqual(mock.executed,plan.steps.map(\.id))
 let stopped=MockComputerAdapter(),waitingAgent=ComputerUseAgent();stopped.waiting=true;waitingAgent.register(stopped)
 await waitingAgent.start(plan);expectEqual(waitingAgent.task?.status,.waiting);expectEqual(stopped.executed.count,1)
 var draft=try unwrapGoal("Open ChatGPT and type Hello without submitting");draft.browser="Arc"
 expectFalse(try WorkflowPlanner.plan(draft,original:"Open ChatGPT and type Hello without submitting").steps.contains{$0.operation == .submitPrompt})
 for sequence in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]] {
 var chord=ActivationChord();var keys=[false,false,false];var activations=0
 for key in sequence {keys[key]=true;if chord.update(control:keys[0],option:keys[1],command:keys[2]){activations+=1}}
 expectEqual(activations,1);expectFalse(chord.update(control:true,option:true,command:true))
 expectFalse(chord.update(control:false,option:true,command:true));expectTrue(chord.update(control:true,option:true,command:true))
 chord.reset();expectTrue(chord.update(control:true,option:true,command:true))
 }
 print("CHECK smart agent: spoken ChatGPT queries, correction, draft/preview/sensitive policy, five-step execution, readiness, six shortcut press orders")
}
private func unwrapGoal(_ text:String)throws->WorkflowRequest {guard let goal=WorkflowPlanner.parse(text),goal.kind == .chatGPT else{throw VoiceyError.invalid("ChatGPT goal was not parsed: "+text)};return goal}
