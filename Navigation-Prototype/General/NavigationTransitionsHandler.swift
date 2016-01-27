import UIKit

class NavigationTransitionsHandler {
    
    private let navigationController: UINavigationController
    private let transitionsStackClient: TransitionContextsStackClient
    
    init(
        navigationController: UINavigationController,
        transitionsStackClient: TransitionContextsStackClient = TransitionContextsStackClient())
    {
        self.navigationController = navigationController
        self.transitionsStackClient = transitionsStackClient
    }
    
    weak var navigationTransitionsHandlerDelegate: NavigationTransitionsHandlerDelegate?
}

// MARK: - TransitionsHandler
extension NavigationTransitionsHandler : TransitionsHandler {
    
    func performTransition(@noescape contextCreationClosure closure: (generatedTransitionId: TransitionId) -> ForwardTransitionContext) {
        if shouldForwardPerformingTransition() {
            // в цепочке обработчиков переходов есть дочерний, передаем управление ему
            forwardPerformingTransition(contextCreationClosure: closure)
        }
        else {
            // выполняем переход
            let transitionId = generateTransitionId()
            let context = closure(generatedTransitionId: transitionId)
            performTransitionAndCommit(context: context, transitionId: transitionId)
        }
    }
    
    func undoTransitions(tilTransitionId transitionId: TransitionId) {
        if shouldForwardUndoingTransitions(tilTransitionId: transitionId) {
            // нужно вернуться на контроллер, который не находится в истории переходов текущего обработчика
            // передаем управление дочернему обработчику
            forwardUndoingTransitions(tilTransitionId: transitionId)
        }
        else {
            // нужно вернуться на контроллер, который находится в истории переходов текущего обработчика
            // скрываем дочерние обработчики и выполняем обратный переход
            forwardUndoingAllChainedTransitions()
            undoTransitionsAndCommit(tilId: transitionId)
        }
    }
    
    func undoTransitions(tilTransitionIdPreceding transitionId: TransitionId) {
        if shouldForwardUndoingTransitions(tilTransitionIdPreceding: transitionId) {
            // нужно отменить переход, который не находится в истории переходов текущего обработчика
            // передаем управление дочернему обработчику
            forwardUndoingTransitions(tilTransitionIdPreceding: transitionId)
        }
        else {
            // нужно отменить переход, который находится в истории переходов текущего обработчика
            // скрываем дочерние обработчики и выполняем обратный переход
            forwardUndoingAllChainedTransitions()
            undoTransitionAndCommit(id: transitionId)
        }
    }
    
    func undoAllChainedTransitions() {
        forwardUndoingAllChainedTransitions()
        undoChainedTransitionAndCommit()
    }
    
    func undoAllTransitions() {
        forwardUndoingAllChainedTransitions()
        undoChainedTransitionAndCommit()
        undoAllTransitionsAndCommit()
    }
    
    func resetWithTransition(
        @noescape contextCreationClosure closure: (generatedTransitionId: TransitionId) -> ForwardTransitionContext)
    {
        forwardUndoingAllChainedTransitions()
        undoChainedTransitionAndCommit()
        
        let transitionId = generateTransitionId()
        let context = closure(generatedTransitionId: transitionId)
        resetAllTransitionsAndCommit(withContext: context)
    }
}

// MARK: - private transitions perfroming and undoing
private extension NavigationTransitionsHandler {
    
    /**
     Геренирует новый псевдослучайный уникальный идентификатор переходаы
     */
    func generateTransitionId() -> TransitionId {
        let result = NSUUID().UUIDString
        return result
    }
    
    /**
     Осуществляет переход на новый модуль согласно описанию и сохраняет запись о переходе.
     Переход может быть отложен (например, вызовом окна авторизации)
     */
    func performTransitionAndCommit(context context: ForwardTransitionContext, transitionId: TransitionId) {
        if let sourceViewController = navigationController.topViewController,
            let animationContext = createAnimationContextForForwardTransition(context: context) {
                
                context.animator.animatePerformingTransition(animationContext: animationContext)
                
                commitPerformedTransition(
                    context: context,
                    sourceViewController: sourceViewController,
                    transitionId: transitionId
                )
                
                if context.targetTransitionsHandler !== self {
                    // показали модальное окно или поповер
                    navigationTransitionsHandlerDelegate?.navigationTransitionsHandlerDidBecomeFirstResponder(self)
                }
        }
    }
    
    /**
     Выполняет обратные переходы, пока не вернется на нужный контроллер
     */
    func undoTransitionsAndCommit(tilId transitionId: TransitionId) {
        if let lastRestoredChainedTransition = lastRestoredChainedTransition {
            // будет сокрытие модального окна или поповера
            let didFinish = lastRestoredChainedTransition.sourceViewController == context.targetViewController
            undoTransitionImpl(context: lastRestoredChainedTransition)
            commitUndoneLastTransition()
            
            // сокрытие модального окна или поповера могло сразу привести нас к нужному контроллеру
            if didFinish { return }
        }

        if let overalRestoredTransition = overalRestoredTransitionForBackwardTransition(tilId: transitionId) {
            // будет popToViewController
            undoTransitionImpl(context: overalRestoredTransition)
            commitUndoneTransitions(tilId: transitionId)
        }
    }
    
    func undoTransitionAndCommit(id transitionId: TransitionId) {

    }

    /**
     Убирает модальное окно или поповер текущего обработчика переходов
     */
    func undoChainedTransitionAndCommit() {
        if let lastRestoredChainedTransition = lastRestoredChainedTransition {
            undoTransitionImpl(context: lastRestoredChainedTransition)
            commitUndoneLastTransition()
            navigationTransitionsHandlerDelegate?.navigationTransitionsHandlerDidResignFirstResponder(self)
        }
    }
    
    /**
     Выполняет обратный переход согласно описанию (отменяет переход)
     */
    func undoTransitionImpl(context context: RestoredTransitionContext) {
        if let animationContext = createAnimationContextForRestoredTransition(context: context) {
            context.animator.animateUndoingTransition(animationContext: animationContext)
        }
    }
    
    /**
     Последовательно возвращается в начало по своей истории переходов
     */
    func undoAllTransitionsAndCommit() {
        assert(lastRestoredChainedTransition == nil, "you must undo chained transitions first")
        if let overalRestoredTransition = overalRestoredTransition {
            undoTransitionImpl(context: overalRestoredTransition)
            commitUndoneTransitions()
        }
    }
    
    func resetAllTransitionsAndCommit(withContext context: ForwardTransitionContext) {
        assert(lastRestoredChainedTransition == nil, "you must undo chained transitions first")
        if let animationContext = createAnimationContextForForwardTransition(context: context) {
            context.animator.animateResettingWithTransition(animationContext: animationContext)
        }
        commitUndoneTransitions()
    }
}

// MARK: - private transitions history management (commiting to the stack)
private extension NavigationTransitionsHandler {
    /**
     Сохраняет запись о совершенном переходе, чтобы потом иметь возможность отменить переход.
     */
    func commitPerformedTransition(
        context context: ForwardTransitionContext,
        sourceViewController: UIViewController,
        transitionId: TransitionId) {
        
        let completedTransitionContext = CompletedTransitionContext(
            forwardTransitionContext: context,
            sourceViewController: sourceViewController,
            sourceTransitionsHandler: self,
            transitionId: transitionId
        )
        completedTransitionsStack.append(completedTransitionContext)
    }
    
    func commitUndoneLastTransition() {
        completedTransitionsStack.popLast()
    }
    
    func commitUndoneTransitions() {
        completedTransitionsStack.removeAll()
    }
    
    func commitUndoneTransitions(tilId transitionId: TransitionId) {
        completedTransitionsStack.popToContext(context)
    }
}

// MARK: - private transitions forwarding to chained transition hanlders
private extension NavigationTransitionsHandler {
    func shouldForwardPerformingTransition() -> Bool {
        let result = transitionsStackClient.doesTransitionsHandlerHaveChainedTransitionHandlers(self)
        return result
    }
    
    func forwardPerformingTransition(@noescape contextCreationClosure closure: (generatedTransitionId: TransitionId) -> ForwardTransitionContext) {
        let chainedTransitionsHandler = transitionsStackClient.chainedTransitionsHandlerForTransitionsHandler(self)
        assert(chainedTransitionsHandler != nil, "you cannot forward to nil")
        chainedTransitionsHandler?.performTransition(contextCreationClosure: closure)
    }
    
    func shouldForwardUndoingTransitions(tilTransitionId transitionId: TransitionId) -> Bool {
        let context = transitionsStackClient.transitionWithId(transitionId, forTransitionsHandler: self)
        let result = context == nil
        return result
    }
    
    func forwardUndoingTransitions(tilTransitionId transitionId: TransitionId) {
        assert(lastRestoredChainedTransitionsHandler != nil, "you cannot forward to nil")
        lastRestoredChainedTransitionsHandler?.undoTransitions(tilTransitionId: transitionId)
    }
    
    func shouldForwardUndoingTransitions(tilTransitionIdPreceding transitionId: TransitionId) -> Bool {
        return !completedTransitionsStack.canBePoppedToTransition(id: transitionId)
    }
    
    func forwardUndoingTransitions(tilTransitionIdPreceding transitionId: TransitionId) {
        assert(lastRestoredChainedTransitionsHandler != nil, "you cannot forward to nil")
        lastRestoredChainedTransitionsHandler?.undoTransitions(tilTransitionIdPreceding: transitionId)
    }
    
    /**
     Заставляем дочерние обработчики скрыть свои поповеры и убрать свои модальные окна
     */
    func forwardUndoingAllChainedTransitions() {
        lastRestoredChainedTransitionsHandler?.undoAllChainedTransitions()
    }
}

// MARK: - private convenience getters
private extension NavigationTransitionsHandler {
    var lastRestoredTransition: RestoredTransitionContext? {
        return completedTransitionsStack.last
    }
    
    var lastRestoredChainedTransition: RestoredTransitionContext? {
        if let lastRestoredTransition = lastRestoredTransition
            where lastRestoredTransition.sourceTransitionsHandler !== self {
                return lastRestoredTransition
        }
        return nil
    }
    
    /// описание перехода от последнего до первого шага, минуя промежуточные
    var overalRestoredTransition: RestoredTransitionContext? {
        return completedTransitionsStack.lastToFirst
    }
    
    /**
     Описание перехода от контроллера, описанного в context'е до последнего шага, минуя промежуточные
     */
    func overalRestoredTransitionForBackwardTransition(tilId transitionId: TransitionId)
        -> RestoredTransitionContext?
    {
        return completedTransitionsStack.lastToContext(context)
    }
}

// MARK: - private animation parameters creating
private extension NavigationTransitionsHandler {
    
    @warn_unused_result
    func createAnimationSourceParameters(
        transitionStyle transitionStyle: TransitionStyle,
        storableParameters: TransitionStorableParameters?) -> TransitionAnimationSourceParameters? {
        
        switch transitionStyle {
        case .Push, .Modal:
            let result = NavigationAnimationSourceParameters(navigationController: navigationController)
            return result
            
        case .PopoverFromButtonItem(_), .PopoverFromView(_, _):
            guard let popoverStorableParameters = storableParameters as? PopoverTransitionStorableParameters else {
                assert(false, "You passed wrong storable parameters \(storableParameters) for transition style: \(transitionStyle)")
                return nil
            }
            
            let popoverController = popoverStorableParameters.popoverController
            let result = PopoverAnimationSourceParameters(popoverController: popoverController)
            return result
        }
    }
    
    @warn_unused_result
    func createAnimationContextForForwardTransition(context context: ForwardTransitionContext) -> TransitionAnimationContext? {
        guard let animationSourceParameters = createAnimationSourceParameters(
            transitionStyle: context.transitionStyle,
            storableParameters: context.storableParameters)
            else { return nil }
        
        let converter = TransitionContextConverter()
        let result = converter.convertForwardTransition(
            context: context,
            toAnimationContextWithAnimationSourceParameters: animationSourceParameters)
        
        return result
    }
    
    @warn_unused_result
    func createAnimationContextForRestoredTransition(context context: RestoredTransitionContext) -> TransitionAnimationContext? {
        guard let animationSourceParameters = createAnimationSourceParameters(
            transitionStyle: context.transitionStyle,
            storableParameters: context.storableParameters)
            else { return nil }
        
        let converter = TransitionContextConverter()
        let result = converter.convertRestoredTransition(
            context: context,
            toAnimationContextWithAnimationSourceParameters: animationSourceParameters)
        
        return result
    }
}