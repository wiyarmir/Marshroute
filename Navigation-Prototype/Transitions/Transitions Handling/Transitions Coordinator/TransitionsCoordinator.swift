/// Протокол описывает передачу обработки и отмены переходов в центр управления переходами
protocol TransitionsCoordinator: class {
    func coordinatePerformingTransition(
        context context: ForwardTransitionContext,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    
    func coordinatePerformingTransition(
        context context: ForwardTransitionContext,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    
    func coordinateUndoingTransitionsAfter(
        transitionId transitionId: TransitionId,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    
    func coordinateUndoingTransitionsAfter(
        transitionId transitionId: TransitionId,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    
    func coordinateUndoingTransitionWith(
        transitionId transitionId: TransitionId,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    
    func coordinateUndoingTransitionWith(
        transitionId transitionId: TransitionId,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    
    func coordinateUndoingAllChainedTransitions(
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    
    func coordinateUndoingAllTransitions(
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    
    func coordinateResettingWithTransition(
        context context: ForwardTransitionContext,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
}

// MARK: - TransitionsCoordinator Default Impl
extension TransitionsCoordinator where Self: TransitionContextsStackClientProviderHolder {
    func coordinatePerformingTransition(
        context context: ForwardTransitionContext,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        // ищем самого глубокого дочернего анимирующего обработчика, чтобы прокинуть ему обработку перехода
        let animatingTransitionsHandler = selectDeepestChainedAnimatingTransitionsHandlerToPerformOrReset(
            amongAnimatingTransitionsHandlers: [transitionsHandler])
        
        coordinatePerformingTransitionImpl(
            context: context,
            forAnimatingTransitionsHandler: animatingTransitionsHandler
        )
    }
    
    func coordinatePerformingTransition(
        context context: ForwardTransitionContext,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    {
        // будем искать вложенные анимирующие обработчики переходов (например, для split'а, найдем его master и detail)
        // среди видимых анимирующих обработчиков (то есть в выбранном tab'e tabbar'a)
        let animatingTransitionsHandlers = transitionsHandler.visibleTransitionsHandlers
        
        // выбираем из найденных анимирующих обработчиков один с самым глубоким дочерним анимирующим обработчиком
        // и получаем этого дочернего обработчика, чтобы прокинуть ему обработку перехода
        let animatingTransitionsHandler = selectDeepestChainedAnimatingTransitionsHandlerToPerformOrReset(
            amongAnimatingTransitionsHandlers: animatingTransitionsHandlers)
        
        coordinatePerformingTransitionImpl(
            context: context,
            forAnimatingTransitionsHandler: animatingTransitionsHandler
        )
    }
    
    func coordinateUndoingTransitionsAfter(
        transitionId transitionId: TransitionId,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        coordinateUndoingTransitionsImpl(
            afterTransitionId: transitionId,
            includingTransitionWithId: false,
            forAnimatingTransitionsHandler: transitionsHandler
        )
    }
    
    func coordinateUndoingTransitionsAfter(
        transitionId transitionId: TransitionId,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    {
        coordinateUndoingTransitionsImpl(
            afterTransitionId: transitionId,
            includingTransitionWithId: false,
            forContainingTransitionsHandler: transitionsHandler
        )
    }
    
    func coordinateUndoingTransitionWith(
        transitionId transitionId: TransitionId,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        coordinateUndoingTransitionsImpl(
            afterTransitionId: transitionId,
            includingTransitionWithId: true,
            forAnimatingTransitionsHandler: transitionsHandler
        )
    }
    
    func coordinateUndoingTransitionWith(
        transitionId transitionId: TransitionId,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    {
        coordinateUndoingTransitionsImpl(
            afterTransitionId: transitionId,
            includingTransitionWithId: true,
            forContainingTransitionsHandler: transitionsHandler
        )
    }
    
    func coordinateUndoingAllChainedTransitions(
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        // скрываем модальные окна и поповеры, показанных внутри модальных окон и поповеров текущего обработчика
        coordinateUndoingChainedTransitionsIfNeeded(forTransitionsHandler: transitionsHandler)
        
        guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: transitionsHandler)
            else { return }
        
        // отменить нужно только переход с открытием модального окна или поповера
        guard let chainedTransition = stackClient.chainedTransitionForTransitionsHandler(transitionsHandler)
            else { return }
        
        coordinateUndoingTransitionsImpl(
            chainedTransition: chainedTransition,
            pushTransitions: nil,
            forAnimatingTransitionsHandler: transitionsHandler,
            andCommitUndoingTransitionsAfter: chainedTransition.transitionId,
            includingTransitionWithId: true,
            withStackClient: stackClient
        )
    }
    
    func coordinateUndoingAllTransitions(
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        // скрываем модальные окна и поповеры, показанных внутри модальных окон и поповеров текущего обработчика
        coordinateUndoingChainedTransitionsIfNeeded(forTransitionsHandler: transitionsHandler)
        
        guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: transitionsHandler)
            else { return }
        
        // готовим список переходов, которые нужно отменить
        let transitionsToUndo = stackClient.allTransitionsForTransitionsHandler(transitionsHandler)
        
        // переход с открытием модального окна или поповера
        let chainedTransition = transitionsToUndo.chainedTransition
        
        // переходы по навигационному стеку
        let pushTransitions = transitionsToUndo.pushTransitions
        
        guard let firstTransitionId = pushTransitions?.first?.transitionId
            else { return }
        
        coordinateUndoingTransitionsImpl(
            chainedTransition: chainedTransition,
            pushTransitions: pushTransitions,
            forAnimatingTransitionsHandler: transitionsHandler,
            andCommitUndoingTransitionsAfter: firstTransitionId,
            includingTransitionWithId: false,
            withStackClient: stackClient
        )
    }
    
    func coordinateResettingWithTransition(
        context context: ForwardTransitionContext,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        // скрываем модальные окна и поповеры, показанных внутри модальных окон и поповеров текущего обработчика
        coordinateUndoingChainedTransitionsIfNeeded(forTransitionsHandler: transitionsHandler)
        
        // ищем существующую историю переходов или создаем новую
        let stackClient = stackClientProvider.stackClient(forTransitionsHandler: transitionsHandler)
            ?? stackClientProvider.createStackClient(forTransitionsHandler: transitionsHandler)
        
        // ищем идентификатор самого первого перехода
        let transitionsToUndo = stackClient.allTransitionsForTransitionsHandler(transitionsHandler)
        let chainedTransition = transitionsToUndo.chainedTransition
        let pushTransitions = transitionsToUndo.pushTransitions
        
        // скрываем модальные окна и поповеры текущего обработчика переходов
        // удаляем записи о первом и последующих переходах
        if let firstTransitionId = pushTransitions?.first?.transitionId {
            coordinateUndoingTransitionsImpl(
                chainedTransition: chainedTransition,
                pushTransitions: nil, // только модальные окна и поповеры
                forAnimatingTransitionsHandler: transitionsHandler,
                andCommitUndoingTransitionsAfter: firstTransitionId,
                includingTransitionWithId: false,
                withStackClient: stackClient
            )
        }
        
        // вызываем анимации
        transitionsHandler.launchAnimationOfResettingWithTransition(launchingContext: context.animationLaunchingContext)
        
        // создаем новую запись о переходе
        commitResettingWithTransition(
            context: context,
            forTransitionsHandler: transitionsHandler,
            withStackClient: stackClient
        )
    }
}

// MARK: - helpers
private extension TransitionsCoordinator where Self: TransitionContextsStackClientProviderHolder {
    func coordinatePerformingTransitionImpl(
        context context: ForwardTransitionContext,
        forAnimatingTransitionsHandler animatingTransitionsHandler: AnimatingTransitionsHandler?)
    {
        guard let animatingTransitionsHandler = animatingTransitionsHandler
            else { assert(false, "к этому моменту должен быть найден анимирующий обработчик"); return }
        
        guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: animatingTransitionsHandler)
            else { assert(false, "сначала нужно было делать resetWithTransitions, а не performTransition"); return }
        
        // вызываем анимации
        animatingTransitionsHandler.launchAnimationOfPerformingTransition(launchingContext: context.animationLaunchingContext)
        
        // создаем новую запись о переходе
        commitPerformingTransition(
            context: context,
            byAnimatingTransitionsHandler: animatingTransitionsHandler,
            withStackClient: stackClient
        )
    }

    func coordinateUndoingTransitionsImpl(
        afterTransitionId transitionId: TransitionId,
        includingTransitionWithId: Bool,
        forAnimatingTransitionsHandler transitionsHandler: AnimatingTransitionsHandler)
    {
        // ищем дочернего обработчика переходов, ранее выполнившего отменяемый переход
        let animatingTransitionsHandler = selectAnimatingTransitionsHandler(
            amongAnimatingTransitionsHandlers: [transitionsHandler],
            toUndoTransitionsAfterId: transitionId,
            includingTransitionWithId: includingTransitionWithId)
        
        coordinateUndoingTransitionsImpl(
            afterTransitionId: transitionId,
            includingTransitionWithId: includingTransitionWithId,
            forSelectedAnimatingTransitionsHandler: animatingTransitionsHandler
        )
    }
    
    func coordinateUndoingTransitionsImpl(
        afterTransitionId transitionId: TransitionId,
        includingTransitionWithId: Bool,
        forContainingTransitionsHandler transitionsHandler: ContainingTransitionsHandler)
    {
        // будем искать вложенные анимирующие обработчики переходов (например, для split'а, найдем его master и detail)
        // среди всех анимирующих обработчиков (то есть среди всех tab'ов tabbar'a)
        let animatingTransitionsHandlers = transitionsHandler.allTransitionsHandlers
        
        // выбираем из найденных анимирующих обработчиков тот, что ранее выполнял отменяемый переход
        let animatingTransitionsHandler = selectAnimatingTransitionsHandler(
            amongAnimatingTransitionsHandlers: animatingTransitionsHandlers,
            toUndoTransitionsAfterId: transitionId,
            includingTransitionWithId: includingTransitionWithId)
        
        coordinateUndoingTransitionsImpl(
            afterTransitionId: transitionId,
            includingTransitionWithId: includingTransitionWithId,
            forSelectedAnimatingTransitionsHandler: animatingTransitionsHandler
        )
    }
    
    func coordinateUndoingTransitionsImpl(
        afterTransitionId transitionId: TransitionId,
        includingTransitionWithId: Bool,
        forSelectedAnimatingTransitionsHandler animatingTransitionsHandler: AnimatingTransitionsHandler?)
    {
        guard let animatingTransitionsHandler = animatingTransitionsHandler
            else { assert(false, "к этому моменту должен быть найден обработчик, выполнивший переход с этим id"); return }
        
        guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: animatingTransitionsHandler)
            else { return }
        
        // готовим список переходов, которые нужно отменить
        let transitionsToUndo = stackClient.transitionsAfter(
            transitionId: transitionId,
            forTransitionsHandler: animatingTransitionsHandler,
            includingTransitionWithId: includingTransitionWithId
        )
        
        // переход с открытием модального окна или поповера
        let chainedTransition = transitionsToUndo.chainedTransition
        
        // переходы по навигационному стеку
        let pushTransitions = transitionsToUndo.pushTransitions
        
        coordinateUndoingTransitionsImpl(
            chainedTransition: chainedTransition,
            pushTransitions: pushTransitions,
            forAnimatingTransitionsHandler: animatingTransitionsHandler,
            andCommitUndoingTransitionsAfter: transitionId,
            includingTransitionWithId: includingTransitionWithId,
            withStackClient: stackClient
        )
    }
    
    func coordinateUndoingTransitionsImpl(
        chainedTransition chainedTransition: RestoredTransitionContext?,
        pushTransitions: [RestoredTransitionContext]?,
        forAnimatingTransitionsHandler animatingTransitionsHandler: AnimatingTransitionsHandler,
        andCommitUndoingTransitionsAfter transitionId: TransitionId,
        includingTransitionWithId: Bool,
        withStackClient stackClient: TransitionContextsStackClient)
    {
        // скрываем модальные окна и поповеры, показанных внутри модальных окон и поповеров текущего обработчика
        coordinateUndoingChainedTransitionsIfNeeded(forTransitionsHandler: animatingTransitionsHandler)
        
        // вызываем анимации сокрытия модальных окон и поповеров
        if let animationLaunchingContext = chainedTransition?.animationLaunchingContext {
            animatingTransitionsHandler.launchAnimationOfUndoingTransition(launchingContext: animationLaunchingContext)
        }
        
        // вызываем анимации возвращения по навигационному стеку, минуя промежуточные переходы
        if let animationLaunchingContext = pushTransitions?.first?.animationLaunchingContext {
            animatingTransitionsHandler.launchAnimationOfUndoingTransition(launchingContext: animationLaunchingContext)
        }
        
        // удаляем записи об отмененных переходах
        commitUndoingTransitionsAfter(
            transitionId: transitionId,
            includingTransitionWithId: includingTransitionWithId,
            forTransitionsHandler: animatingTransitionsHandler,
            withStackClient: stackClient
        )
    }
    
    func coordinateUndoingChainedTransitionsIfNeeded(forTransitionsHandler transitionsHandler: TransitionsHandler)
    {
        // по-хорошему нужно убрать все модальные окна и поповеры дочерних обработчиков переходов.
        // но обнаружились следующие особенности UIKit'а
        //
        // 1. iOS 8, 9:     если скрывать последовательность из поповеров,
        //                      то UIKit падает при анимировании больших (> 3) последовательностей
        //                  если не скрывать последовательности из поповеров, а скрывать только нижний,
        //                      то UIKit отрабатывает правильно
        // 2. iOS 7:        если скрывать последовательность из поповеров,
        //                      то UIKit отрабатывает правильно
        //                  если не скрывать последовательности из поповеров, а скрывать только нижний,
        //                      то UIKit падает, потому что ```popover dealloc reached while popover is visible```
        // 3. iOS 7, 8, 9:  если скрывать последовательность из модальных окон,
        //                      то UIKit не падает, но просто не выполняет сокрытие примерно на середине последовательности
        //
        // в итоге договорились  не убирать дочерние модальные окна и поповеры,
        // а на iOS 7 не использовать поповеры вообще или использовать аккуратно:
        //
        // а) на iOS 7 не показывать поповер в поповере
        // б) на iOS 7 не показывать поповеры внутри модальных окон
        // в) игнорировать пункты а) и б), но не вызывать сокрытие целой цепочки модальных окон и поповеров
        
        // guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: transitionsHandler)
        //     else { return }
        // let chainedTransitionsHandlerBox = stackClient.chainedTransitionsHandlerBoxForTransitionsHandler(self)
        // chainedTransitionsHandlerBox?.unbox().undoAllChainedTransitions()
    }
}

// MARK: - fetching data from the history
private extension TransitionsCoordinator where Self: TransitionContextsStackClientProviderHolder {
    
    /// Выбор из обработчиков переходов одного с самым глубоким дочерним обработчиком.
    /// Возвращается найденный самый глубокий обработчик, чтобы прокинуть ему обработку перехода
    func selectDeepestChainedAnimatingTransitionsHandlerToPerformOrReset(
        amongAnimatingTransitionsHandlers transitionsHandlers: [AnimatingTransitionsHandler]?)
        -> AnimatingTransitionsHandler?
    {
        guard let transitionsHandlers = transitionsHandlers
            else { return nil }
        
        // нужно найти максимально вложенного дочернего обработчика переходов
        var chainedTransitionsHandlers = [AnimatingTransitionsHandler]()
        
        for transitionsHandler in transitionsHandlers {
            guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: transitionsHandler)
                else { continue }
            
            guard let chainedTransitionsHandlerBox = stackClient.chainedTransitionsHandlerBoxForTransitionsHandler(transitionsHandler)
                else { continue }
            
            if let animatingTransitionsHandler = chainedTransitionsHandlerBox.unboxAnimatingTransitionsHandler() {
                chainedTransitionsHandlers.append(animatingTransitionsHandler)
            }
            else if let chainedTransitionsHandler = chainedTransitionsHandlerBox.unboxContainingTransitionsHandler(),
                let childAnimatingTransitionsHandlers = chainedTransitionsHandler.visibleTransitionsHandlers
            {
                chainedTransitionsHandlers.appendContentsOf(childAnimatingTransitionsHandlers)
            }
        }
        
        // если нашли несколько дочерних обработчиков на одинаковой глубине вложенности, то берем любой.
        // у Split'а будет master, если ни master, ни detail не показывали модальных окон или поповеров
        if chainedTransitionsHandlers.isEmpty {
            return transitionsHandlers.first
        }
        
        // иначе продолжаем искать на следующей глубине вложенности
        return selectDeepestChainedAnimatingTransitionsHandlerToPerformOrReset(amongAnimatingTransitionsHandlers: chainedTransitionsHandlers)
    }
    
    /// Поиск обработчика переходов, выполнявшего переход с переданным id.
    /// Если такой не найден, поиск продолжается по дочерним обработчикам
    func selectAnimatingTransitionsHandler(
        amongAnimatingTransitionsHandlers transitionsHandlers: [AnimatingTransitionsHandler]?,
        toUndoTransitionsAfterId transitionId: TransitionId,
        includingTransitionWithId: Bool)
        -> AnimatingTransitionsHandler?
    {
        guard let transitionsHandlers = transitionsHandlers
            else { return nil }
        
        for transitionsHandler in transitionsHandlers {
            guard let stackClient = stackClientProvider.stackClient(forTransitionsHandler: transitionsHandler)
                else { continue }
            
            // если какой-то обработчик выполнял переход с переданным id, возвращаем его
            if (stackClient.transitionWith(transitionId: transitionId, forTransitionsHandler: transitionsHandler) != nil) {
                return transitionsHandler
            }
            
            // иначе смотрим дочерние обработчики
            var chainedTransitionsHandlerBox = stackClient.chainedTransitionsHandlerBoxForTransitionsHandler(transitionsHandler)

            while chainedTransitionsHandlerBox != nil {
                // если дочерний - анимирующий
                if let chainedAnimatingTransitionsHandler = chainedTransitionsHandlerBox!.unboxAnimatingTransitionsHandler() {
                    guard let chainedStackClient = stackClientProvider.stackClient(forTransitionsHandler: chainedAnimatingTransitionsHandler)
                        else { assert(false); break }
                    
                    // если какой-то дочерний анимирующий обработчик выполнял переход с переданным id, возвращаем его
                    if (chainedStackClient.transitionWith(
                        transitionId: transitionId,
                        forTransitionsHandler: chainedAnimatingTransitionsHandler) != nil)
                    {
                        return chainedAnimatingTransitionsHandler
                    }
                    
                    // иначе продолжаем искать среди его дочерних обработчиков
                    chainedTransitionsHandlerBox = chainedStackClient.chainedTransitionsHandlerBoxForTransitionsHandler(
                        chainedAnimatingTransitionsHandler)
                }
                // если дочерний - содержащий
                else if let chainedContainingTransitionsHandler = chainedTransitionsHandlerBox!.unboxContainingTransitionsHandler(),
                    let childAnimatingTransitionsHandlers = chainedContainingTransitionsHandler.allTransitionsHandlers
                {
                    // если какой-то из вложенных обработчиков содержащего обработчика выполнял переход с переданным Id, возвращаем его
                    let subresult = selectAnimatingTransitionsHandler(
                        amongAnimatingTransitionsHandlers: childAnimatingTransitionsHandlers,
                        toUndoTransitionsAfterId: transitionId,
                        includingTransitionWithId: includingTransitionWithId)
                    
                    if subresult != nil {
                        return subresult
                    }
                    
                    // иначе обрываем цикл
                    chainedTransitionsHandlerBox = nil
                }
                else { assert(false, "добавились новые виды обработчиков. нужно дописать код"); break }
            }
        }
        return nil
    }
}

// MARK: - committing to the history
private extension TransitionsCoordinator where Self: TransitionContextsStackClientProviderHolder {
    func commitPerformingTransition(
        context context: ForwardTransitionContext,
        byAnimatingTransitionsHandler animatingTransitionsHandler: AnimatingTransitionsHandler,
        withStackClient stackClient: TransitionContextsStackClient)
    {
        let fixedContext: ForwardTransitionContext = (context.needsTargetTransitionsHandler)
            ? ForwardTransitionContext(context: context, changingTargetAnimatingTransitionsHandler: animatingTransitionsHandler)
            : context
        
        // ищем последний переход, выполненный анимирующим обработчиком
        guard let lastTransition = stackClient.lastTransitionForTransitionsHandler(animatingTransitionsHandler) else {
            assert(false, "нужно было вызывать resetWithTransition(context:). а не performTransition(context:)")
            return
        }
        
        // достаем view controller, откуда ушли, в результате текущего перехода
        let completedTransitionContext = CompletedTransitionContext(
            forwardTransitionContext: fixedContext,
            sourceViewController: lastTransition.targetViewController, // откуда ушли
            sourceTransitionsHandler: animatingTransitionsHandler // кем выполнен переход
        )
        
        guard completedTransitionContext != nil
            else { assert(false); return }
        
        // создаем новую запись о переходе
        stackClient.appendTransition(
            context: completedTransitionContext!,
            forTransitionsHandler: animatingTransitionsHandler
        )
    }
    
    func commitUndoingTransitionsAfter(
        transitionId transitionId: TransitionId,
        includingTransitionWithId: Bool,
        forTransitionsHandler transitionsHandler: TransitionsHandler,
        withStackClient stackClient: TransitionContextsStackClient)
    {
        stackClient.deleteTransitionsAfter(
            transitionId: transitionId,
            forTransitionsHandler: transitionsHandler,
            includingTransitionWithId: includingTransitionWithId
        )
    }
    
    func commitResettingWithTransition(
        context context: ForwardTransitionContext,
        forTransitionsHandler animatingTransitionsHandler: AnimatingTransitionsHandler,
        withStackClient stackClient: TransitionContextsStackClient)
    {
        guard !context.needsTargetTransitionsHandler
            else { assert(false, "проставьте это значение раньшье"); return }
        
        let completedTransitionContext = CompletedTransitionContext(
            forwardTransitionContext: context,
            sourceViewController: context.targetViewController, // при reset source == target
            sourceTransitionsHandler: animatingTransitionsHandler // кем выполнен переход
        )
        
        guard completedTransitionContext != nil
            else { assert(false); return }
        
        // создаем новую запись о переходе
        stackClient.appendTransition(
            context: completedTransitionContext!,
            forTransitionsHandler: animatingTransitionsHandler
        )
    }
}