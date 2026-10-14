import Foundation
import VoiceyCore
@MainActor private final class AdaptiveFixture:ComputerAdapter {
 let descriptor=AdapterDescriptor("adaptive fixture",[.inspectInterface,.setControlValue],verification:"fixture values")
 var value="",executed=0
 func observe(_ s:ComputerStep) async throws->Verification{Verification(s.operation == .inspectInterface || value==s.arguments.text ? .success:.unknown,"Observed fixture: \(value)")}
 func execute(_ s:ComputerStep) async throws->AdapterResult{value=s.arguments.text;executed+=1;return .verified(try await observe(s))}
}
@MainActor func adaptiveComputerChecks() async throws {
 let adapter=AdaptiveFixture(),agent=ComputerUseAgent();agent.register(adapter)
 var a=OperationArguments();a.application="Fixture"
 let initial=ComputerStep(.inspectInterface,a,title:"Observe")
 agent.continuation={task in
 if adapter.value=="Local goal"{return .complete(Verification(.success,"Observed exact requested value"))}
 var field=a;field.text="Local goal"
 return .steps([ComputerStep(.setControlValue,field,title:"Fill",after:[task.steps.last!.id])])
 }
 await agent.start(ComputerTask(request:"Fill Local goal",intention:"Exact value",steps:[initial]))
 expectEqual(agent.task?.status,.complete);expectEqual(adapter.executed,1);expectEqual(agent.task?.steps.count,2)
 agent.configuration.maxSteps=1;adapter.value=""
 await agent.start(ComputerTask(request:"Fill Local goal",intention:"Exact value",steps:[initial]))
 expectEqual(agent.task?.status,.failed);expectEqual(adapter.executed,1)
 agent.configuration.maxSteps=24
 agent.continuation={_ in .complete(Verification(.unknown,"Model says done without proof"))}
 await agent.start(ComputerTask(request:"Observe",intention:"Exact value",steps:[initial]))
 expectEqual(agent.task?.status,.failed)
 agent.continuation={_ in .steps([])}
 await agent.start(ComputerTask(request:"Observe",intention:"Exact value",steps:[initial]))
 expectEqual(agent.task?.status,.failed)
 agent.continuation={_ in .wait("The next control is ambiguous")}
 await agent.start(ComputerTask(request:"Observe",intention:"Exact value",steps:[initial]))
 expectEqual(agent.task?.status,.waiting);expectTrue(agent.pending != nil);agent.cancel();expectEqual(agent.task?.status,.cancelled)
 agent.continuation={_ in try await Task.sleep(nanoseconds:100_000_000);return .complete(Verification(.success,"late"))}
 let run=Task{await agent.start(ComputerTask(request:"Observe",intention:"Exact value",steps:[initial]))}
 try await Task.sleep(nanoseconds:20_000_000);agent.cancel();await run.value
 expectEqual(agent.task?.status,.cancelled)
 print("CHECK adaptive executor: grounded continuation, shared step budget, unknown completion rejection, empty plan rejection, clarification, cancellation of late planning")
}
