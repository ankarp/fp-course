{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE RebindableSyntax #-}
{-# LANGUAGE OverloadedStrings #-}

module Course.StateT where

import Course.Core
import Course.ExactlyOne
import Course.Optional
import Course.List
import Course.Functor
import Course.Applicative
import Course.Monad
import Course.State
import qualified Data.Set as S
import qualified Prelude as P

-- $setup
-- >>> import Test.QuickCheck
-- >>> import qualified Prelude as P(fmap)
-- >>> instance Arbitrary a => Arbitrary (List a) where arbitrary = P.fmap listh arbitrary

-- | A `StateT` is a function from a state value `s` to a functor k of (a produced value `a`, and a resulting state `s`).
newtype StateT s k a =
  StateT {
    runStateT ::
      s
      -> k (a, s)
  }

-- | Implement the `Functor` instance for @StateT s k@ given a @Functor k@.
--
-- >>> runStateT ((+1) <$> (pure 2) :: StateT Int List Int) 0
-- [(3,0)]
instance Functor k => Functor (StateT s k) where
  (<$>) ::
    (a -> b)
    -> StateT s k a
    -> StateT s k b
  (<$>) f st =
    let func = runStateT st  -- s -> k (a, s)
        g (a, s) = (f a, s)  -- (a, s) -> (b, s)
        g' = (<$>) g         -- k (a, s) -> k (b, s)
    in StateT { runStateT = g' . func}

-- | Implement the `Applicative` instance for @StateT s k@ given a @Monad k@.
--
-- >>> runStateT (pure 2) 0
-- (2,0)
--
-- >>> runStateT ((pure 2) :: StateT Int List Int) 0
-- [(2,0)]
--
-- >>> runStateT (pure (+2) <*> ((pure 2) :: StateT Int List Int)) 0
-- [(4,0)]
--
-- >>> runStateT (StateT (\s -> Full ((+2), s ++ (1:.Nil))) <*> (StateT (\s -> Full (2, s ++ (2:.Nil))))) (0:.Nil)
-- Full (4,[0,1,2])
--
-- >>> runStateT (StateT (\s -> ((+2), s ++ (1:.Nil)) :. ((+3), s ++ (1:.Nil)) :. Nil) <*> (StateT (\s -> (2, s ++ (2:.Nil)) :. Nil))) (0:.Nil)
-- [(4,[0,1,2]),(5,[0,1,2])]
instance Monad k => Applicative (StateT s k) where
  pure ::
    a
    -> StateT s k a
  pure a =
    let f s = return (a, s)
    in StateT { runStateT = f } 
  (<*>) ::
    StateT s k (a -> b)
    -> StateT s k a
    -> StateT s k b
  StateT f <*> StateT a =      -- a :: s -> k(a, s)
    let rs = \s ->
          let f' = f s      -- k (a -> b, s)
              ap (g, t) =   -- g :: a -> b, t :: s, a t :: k (a, s)
                let fab (z, u) = (g z, u)   -- (a, s) -> (b, s)
                in fab <$> (a t)  -- k (b, s)
          in ap =<< f'
    in StateT rs

-- | Implement the `Monad` instance for @StateT s k@ given a @Monad k@.
-- Make sure the state value is passed through in `bind`.
--
-- >>> runStateT ((const $ putT 2) =<< putT 1) 0
-- ((),2)
--
-- >>> let modify f = StateT (\s -> pure ((), f s)) in runStateT (modify (+1) >>= \() -> modify (*2)) 7
-- ((),16)
instance Monad k => Monad (StateT s k) where
  (=<<) ::
    (a -> StateT s k b)
    -> StateT s k a
    -> StateT s k b
  f =<< StateT m =      -- m :: s -> k (a, s)
    let rs = \s ->
          let ms = m s  -- k (a, s)
              ap (a', s') = (runStateT $ f a') s'    -- a' :: a, f a' :: StateT s k b
                                                     -- k (b, s), hence
                                                     -- ap :: (a, s) -> k (b, s)
          in ap =<< ms
    in StateT rs

-- | A `State'` is `StateT` specialised to the `ExactlyOne` functor.
type State' s a =
  StateT s ExactlyOne a

-- | Provide a constructor for `State'` values
--
-- >>> runStateT (state' $ runState $ put 1) 0
-- ExactlyOne ((),1)
state' ::
  (s -> (a, s))
  -> State' s a
state' f = StateT $ \s -> ExactlyOne $ f s
-- | Provide an unwrapper for `State'` values.
--
-- >>> runState' (state' $ runState $ put 1) 0
-- ((),1)
runState' ::
  State' s a
  -> s
  -> (a, s)
runState' (StateT f) s =
  let ExactlyOne (a, s') = f s
  in (a, s')

-- | Run the `StateT` seeded with `s` and retrieve the resulting state.
--
-- >>> execT (StateT $ \s -> Full ((), s + 1)) 2
-- Full 3
execT ::
  Functor k =>
  StateT s k a
  -> s
  -> k s
execT (StateT f) s = snd <$> f s

-- | Run the `State'` seeded with `s` and retrieve the resulting state.
--
-- >>> exec' (state' $ \s -> ((), s + 1)) 2
-- 3
exec' ::
  State' s a
  -> s
  -> s
exec' f s = snd $ runState' f s

-- | Run the `StateT` seeded with `s` and retrieve the resulting value.
--
-- >>> evalT (StateT $ \s -> Full (even s, s + 1)) 2
-- Full True
evalT ::
  Functor k =>
  StateT s k a
  -> s
  -> k a
evalT (StateT f) s = fst <$> f s

-- | Run the `State'` seeded with `s` and retrieve the resulting value.
--
-- >>> eval' (state' $ \s -> (even s, s + 1)) 5
-- False
eval' ::
  State' s a
  -> s
  -> a
eval' (StateT f) s =
  let ExactlyOne (a, _) = f s
  in a

-- | A `StateT` where the state also distributes into the produced value.
--
-- >>> (runStateT (getT :: StateT Int List Int) 3)
-- [(3,3)]
getT ::
  Applicative k =>
  StateT s k s
getT = StateT $ \s -> pure (s, s)

-- | A `StateT` where the resulting state is seeded with the given value.
--
-- >>> runStateT (putT 2) 0
-- ((),2)
--
-- >>> runStateT (putT 2 :: StateT Int List ()) 0
-- [((),2)]
putT ::
  Applicative k =>
  s
  -> StateT s k ()
putT s = StateT $ \_ -> pure ((), s)

-- | Remove all duplicate elements in a `List`.
--
-- /Tip:/ Use `filtering` and `State'` with a @Data.Set#Set@.
--
-- prop> \xs -> distinct' xs == distinct' (flatMap (\x -> x :. x :. Nil) xs)
distinct' ::
  Ord a =>
  List a
  -> List a
distinct' aas =  -- aas :: List a
  let init_state = S.empty :: S.Set a
      -- k is State' (S.Set a) :: * -> *
      f :: Ord a => a -> State' (S.Set a) Bool   -- :: a -> k Bool
      f a' = state' $ \s' -> (not $ S.member a' s', S.insert a' s')
      res = filtering f aas  -- k (List a), hence State' (S.Set a) (List a)
  in eval' res init_state

-- | Remove all duplicate elements in a `List`.
-- However, if you see a value greater than `100` in the list,
-- abort the computation by producing `Empty`.
--
-- /Tip:/ Use `filtering` and `StateT` over `Optional` with a @Data.Set#Set@.
--
-- >>> distinctF $ listh [1,2,3,2,1]
-- Full [1,2,3]
--
-- >>> distinctF $ listh [1,2,3,2,1,101]
-- Empty
distinctF ::
  (Ord a, Num a) =>
  List a
  -> Optional (List a)
distinctF aas =    -- aas :: List a
  let init_state = S.empty :: S.Set a
      -- k is State (S.Set a) Optional  :: * -> *
      f :: (Ord a, Num a) => a -> StateT (S.Set a) Optional Bool  -- :: a -> k Bool
      f a' =
        let rs s'
              | a' >= 100 = Empty
              | otherwise = Full (not $ S.member a' s', S.insert a' s')
        in StateT rs
      res = filtering f aas   -- State (S.Set a) Optional (List a)
  in evalT res init_state

-- | An `OptionalT` is a functor of an `Optional` value.
data OptionalT k a =
  OptionalT {
    runOptionalT ::
      k (Optional a)
  }

-- | Implement the `Functor` instance for `OptionalT k` given a Functor k.
--
-- >>> runOptionalT $ (+1) <$> OptionalT (Full 1 :. Empty :. Nil)
-- [Full 2,Empty]
instance Functor k => Functor (OptionalT k) where
  (<$>) ::
    (a -> b)
    -> OptionalT k a
    -> OptionalT k b
  f <$> OptionalT g = OptionalT $ lift1 f <$> g

-- | Implement the `Applicative` instance for `OptionalT k` given a Monad k.
--
-- /Tip:/ Use `onFull` to help implement (<*>).
--
-- >>> runOptionalT $ OptionalT Nil <*> OptionalT (Full 1 :. Full 2 :. Nil)
-- []
--
-- >>> runOptionalT $ OptionalT (Full (+1) :. Full (+2) :. Nil) <*> OptionalT Nil
-- []
--
-- >>> runOptionalT $ OptionalT (Empty :. Nil) <*> OptionalT (Empty :. Nil)
-- [Empty]
--
-- >>> runOptionalT $ OptionalT (Full (+1) :. Empty :. Nil) <*> OptionalT (Empty :. Nil)
-- [Empty,Empty]
--
-- >>> runOptionalT $ OptionalT (Empty :. Nil) <*> OptionalT (Full 1 :. Full 2 :. Nil)
-- [Empty]
--
-- >>> runOptionalT $ OptionalT (Full (+1) :. Empty :. Nil) <*> OptionalT (Full 1 :. Full 2 :. Nil)
-- [Full 2,Full 3,Empty]
--
-- >>> runOptionalT $ OptionalT (Full (+1) :. Full (+2) :. Nil) <*> OptionalT (Full 1 :. Empty :. Nil)
-- [Full 2,Empty,Full 3,Empty]
instance Monad k => Applicative (OptionalT k) where
  pure ::
    a
    -> OptionalT k a
  pure a = OptionalT $ (return $ Full a)

  (<*>) ::
    OptionalT k (a -> b)
    -> OptionalT k a
    -> OptionalT k b
  OptionalT f <*> OptionalT a =
    OptionalT (f >>= optional (\f' -> (f' <$>) <$> a) (pure Empty))
  -- OptionalT kab <*> OptionalT ka =
  --   -- kab :: k (Optional (a -> b))
  --   -- ka  :: k (Optional a)
  --   let val = f =<< kab
  --         where
  --           f 
    -- let val = do
    --       ab <- kab
    --       a <- ka
    --       let b = ab <*> a -- Optional b
    --       return b         -- k (Optional b)
    -- in OptionalT $ val
--    error "todo: Course.StateT (<*>)#instance (OptionalT k)"

-- | Implement the `Monad` instance for `OptionalT k` given a Monad k.
--
-- >>> runOptionalT $ (\a -> OptionalT (Full (a+1) :. Full (a+2) :. Nil)) =<< OptionalT (Full 1 :. Empty :. Nil)
-- [Full 2,Full 3,Empty]
instance Monad k => Monad (OptionalT k) where
  (=<<) ::
    (a -> OptionalT k b)
    -> OptionalT k a
    -> OptionalT k b
  f =<< OptionalT m =
    -- (runOptionalT .  f) :: a -> k (Optional b)
    -- m' :: Optional a
    -- result :: k (Optional b)
    OptionalT $ m >>= (\m' -> onFull (runOptionalT . f) m')

-- | A `Logger` is a pair of a list of log values (`[l]`) and an arbitrary value (`a`).
data Logger l a =
  Logger (List l) a
  deriving (Eq, Show)

-- | Implement the `Functor` instance for `Logger
--
-- >>> (+3) <$> Logger (listh [1,2]) 3
-- Logger [1,2] 6
instance Functor (Logger l) where
  (<$>) ::
    (a -> b)
    -> Logger l a
    -> Logger l b
  f <$> Logger ls a = Logger ls (f a)

-- | Implement the `Applicative` instance for `Logger`.
--
-- >>> pure "table" :: Logger Int P.String
-- Logger [] "table"
--
-- >>> Logger (listh [1,2]) (+7) <*> Logger (listh [3,4]) 3
-- Logger [1,2,3,4] 10
instance Applicative (Logger l) where
  pure ::
    a
    -> Logger l a
  pure a = Logger Nil a

  (<*>) ::
    Logger l (a -> b)
    -> Logger l a
    -> Logger l b
  Logger ls1 f <*> Logger ls2 a = Logger (ls1 ++ ls2) (f a)

-- | Implement the `Monad` instance for `Logger`.
-- The `bind` implementation must append log values to maintain associativity.
--
-- >>> (\a -> Logger (listh [4,5]) (a+3)) =<< Logger (listh [1,2]) 3
-- Logger [1,2,4,5] 6
instance Monad (Logger l) where
  (=<<) ::
    (a -> Logger l b)
    -> Logger l a
    -> Logger l b
  f =<< Logger ls a =
    let Logger ls' b = f a
    in Logger (ls ++ ls') b

-- | A utility function for producing a `Logger` with one log value.
--
-- >>> log1 1 2
-- Logger [1] 2
log1 ::
  l
  -> a
  -> Logger l a
log1 l a = Logger (l :. Nil) a

-- | Remove all duplicate integers from a list. Produce a log as you go.
-- If there is an element above 100, then abort the entire computation and produce no result.
-- However, always keep a log. If you abort the computation, produce a log with the value,
-- "aborting > 100: " followed by the value that caused it.
-- If you see an even number, produce a log message, "even number: " followed by the even number.
-- Other numbers produce no log message.
--
-- /Tip:/ Use `filtering` and `StateT` over (`OptionalT` over `Logger` with a @Data.Set#Set@).
--
-- >>> distinctG $ listh [1,2,3,2,6]
-- Logger ["even number: 2","even number: 2","even number: 6"] (Full [1,2,3,6])
--
-- >>> distinctG $ listh [1,2,3,2,6,106]
-- Logger ["even number: 2","even number: 2","even number: 6","aborting > 100: 106"] Empty
distinctG ::
  (Integral a, Show a) =>
  List a
  -> Logger Chars (Optional (List a))

-- ankarp: study
distinctG x =
  let f a = StateT rs
        where rs s =
                -- log1 :: l a' -> Logger l a'
                -- OptionalT ~ k (Optional a')
                -- rs :: s -> OptionalT (Logger Char) (a, s)
                -- where
                -- k = (Logger Char)
                -- s = S.Set a
                -- a' = (a, s)
                -- x :: List a
                -- filtering :: (a -> k Bool) (List a) -> k (List a)
                -- so need to establish: f :: a -> k Bool
                -- know:
                -- f a :: StateT s' k' a'
                -- where 
                -- where OptionalT ((Logger Char) (Bool, s)), so
                -- k' = (OptionalT . (Logger Char))
                -- = (k Bool) where
                -- k c = OptionalT ((Logger Char) (c, s))
                OptionalT (if a > 100
                          then
                            log1 (fromString ("aborting > 100: " P.++ show a)) Empty
                          else (if even a
                                 then log1 (fromString ("even number: " P.++ show a))
                                 else pure) (Full (a `S.notMember` s, a `S.insert` s)))
      res = filtering f x  -- k'' (List a), hence (OptionalT (Logger l)) (List a)
      -- so (Logger l) play the role of k in `OptionalT k` is a functor.
      -- where k'' c = State s' k' c and k'' is a functor with
      -- k' = (OptionalT . (Logger Char))
      -- evalT ::
      --   Functor k =>
      --   StateT s k a
      --   -> s
      --   -> k a
      val = evalT res S.empty
      -- hence, val :: k' (List a) = (OptionalT (Logger Chars)) (List a)
      -- so, runOptional val :: (Logger Chars) (Optional(List a))
  in runOptionalT val

  -- runOptionalT (evalT (filtering (\a -> StateT (\s ->
  --   OptionalT (if a > 100
  --                then
  --                  log1 (fromString ("aborting > 100: " P.++ show a)) Empty
  --                else (if even a
  --                  then log1 (fromString ("even number: " P.++ show a))
  --                  else pure) (Full (a `S.notMember` s, a `S.insert` s))))) x) S.empty)
--distinctG =
--  error "todo: Course.StateT#distinctG"

onFull ::
  Applicative k =>
  (t -> k (Optional a))
  -> Optional t
  -> k (Optional a)
onFull g o =
  case o of
    Empty ->
      pure Empty
    Full a ->
      g a
