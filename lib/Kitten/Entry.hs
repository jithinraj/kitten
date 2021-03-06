{-|
Module      : Kitten.Entry
Description : Dictionary entries
Copyright   : (c) Jon Purdy, 2016
License     : MIT
Maintainer  : evincarofautumn@gmail.com
Stability   : experimental
Portability : GHC
-}

{-# LANGUAGE OverloadedStrings #-}

module Kitten.Entry
  ( Entry(..)
  ) where

import Data.List (intersperse)
import Kitten.DataConstructor (DataConstructor)
import Kitten.Entry.Category (Category)
import Kitten.Entry.Merge (Merge)
import Kitten.Entry.Parameter (Parameter)
import Kitten.Entry.Parent (Parent)
import Kitten.Name (Qualified)
import Kitten.Origin (Origin)
import Kitten.Signature (Signature)
import Kitten.Term (Term)
import Kitten.Type (Type)
import Text.PrettyPrint.HughesPJClass (Pretty(..))
import qualified Kitten.DataConstructor as DataConstructor
import qualified Kitten.Entry.Category as Category
import qualified Kitten.Pretty as Pretty
import qualified Text.PrettyPrint as Pretty

-- | An entry in the dictionary.
--
-- FIXME: This could use significant cleaning up. We could possibly make each
-- constructor into a separate 'HashMap' in the 'Dictionary'.

data Entry

  -- | A word definition. If the implementation is 'Nothing', this is a
  -- declaration: it can be used for type checking and name resolution, but not
  -- compilation. If the parent is a trait, this is a trait instance, with
  -- instance mangling. If the parent is a type, this is a constructor.
  -- Definitions without signatures are disallowed by the surface syntax, but
  -- they are generated for lifted lambdas, as those have already been
  -- typechecked by the time quotations are flattened into top-level definitions
  -- ("Kitten.Desugar.Quotations").
  = Word !Category !Merge !Origin !(Maybe Parent) !(Maybe Signature)
    !(Maybe (Term Type))

  -- | Untyped metadata from @about@ blocks. Used internally for operator
  -- precedence and associativity.
  | Metadata !Origin !(Term ())

  -- | A link to another entry in the dictionary. Generated by imports and
  -- synonym declarations.
  | Synonym !Origin !Qualified

  -- | A trait to which other entries can link.
  | Trait !Origin !Signature

  -- | A data type with some generic parameters.
  | Type !Origin [Parameter] [DataConstructor]

  -- | An instantiation of a data type, with the given size.
  | InstantiatedType !Origin !Int

  deriving (Show)

instance Pretty Entry where
  pPrint entry = case entry of

    Word category _merge origin mParent mSignature _body -> Pretty.vcat
      [ case category of
        Category.Constructor -> "constructor"  -- of type
        Category.Instance -> "instance"  -- of trait
        Category.Permission -> "permission"
        Category.Word -> "word"
      , Pretty.hsep ["defined at", pPrint origin]
      , case mSignature of
        Just signature -> Pretty.hsep
          ["with signature", Pretty.quote signature]
        Nothing -> "with no signature"
      , case mParent of
        Just parent -> Pretty.hsep
          ["with parent", pPrint parent]
        Nothing -> "with no parent"
      ]

    Metadata origin term -> Pretty.vcat
      [ "metadata"
      , Pretty.hsep ["defined at", pPrint origin]
      , Pretty.hsep ["with contents", pPrint term]
      ]

    Synonym origin name -> Pretty.vcat
      [ "synonym"
      , Pretty.hsep ["defined at", pPrint origin]
      , Pretty.hsep ["standing for", pPrint name]
      ]

    Trait origin signature -> Pretty.vcat
      [ "trait"
      , Pretty.hsep ["defined at", pPrint origin]
      , Pretty.hsep ["with signature", pPrint signature]
      ]

    Type origin parameters ctors -> Pretty.vcat
      [ "type"
      , Pretty.hsep ["defined at", pPrint origin]
      , Pretty.hcat $ "with parameters <"
        : intersperse ", " (map pPrint parameters)
        ++ [">"]
      , Pretty.vcat
        [ "and data constructors"
        , Pretty.nest 4 $ Pretty.vcat
          $ map constructor ctors
        ]
      ]
      where
        constructor ctor = Pretty.hcat
          [ pPrint $ DataConstructor.name ctor
          , " with fields ("
          , Pretty.hcat $ intersperse ", "
            $ map pPrint $ DataConstructor.fields ctor
          , ")"
          ]

    InstantiatedType origin size -> Pretty.vcat
      [ "instantiated type"
      , Pretty.hsep ["defined at", pPrint origin]
      , Pretty.hcat ["with size", pPrint size]
      ]
