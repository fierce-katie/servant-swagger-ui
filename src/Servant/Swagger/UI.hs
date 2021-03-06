{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
{-# LANGUAGE UndecidableInstances       #-}
-----------------------------------------------------------------------------
-- |
-- Module      :  Servant.Swagger.UI
-- Copyright   :  (C) 2016 Oleg Grenrus
-- License     :  BSD3
-- Maintainer  :  Oleg Grenrus <oleg.grenrus@iki.fi>
--
-- Provides 'SwaggerUI' and corresponding 'swaggerUIServer' to embed
-- <http://swagger.io/swagger-ui/ swagger ui> into the application.
--
-- All of UI files are embedded into the binary.
--
-- /An example:/
--
-- @
-- -- | Actual API.
-- type BasicAPI = Get '[PlainText, JSON] Text
--     :\<|> "cat" :> Capture ":name" CatName :> Get '[JSON] Cat
--
-- -- | Swagger schema endpoint.
-- type SwaggerSchemaEndpoint = "swagger.js" :> Get '[JSON] Swagger
--
-- -- | Unhabitated new data type, to be able to refer to API type from the API type.
-- data API
--
-- -- | Underlying API type.
-- --
-- -- NOTE: place BasicAPI last for it not to override SwaggerSchemaEndpoing and SwaggerUI.
-- -- If you place BasicAPI first and it has Raw endpoint at root Swagger schema and UI won't work.
-- type API' = SwaggerSchemaEndpoint
--     :\<|> 'SwaggerUI' "ui" SwaggerSchemaEndpoint API
--     :\<|> BasicAPI
--
-- -- Optionally we can do:
-- --
-- -- type API' = SwaggerSchemaEndpoint
-- --     :\<|> BasicAPI
-- --
-- -- type API = SwaggerUI "ui" SwaggerSchemaEndpoint API'
-- --     :\<|> API'
--
-- -- Unfortunately we have to write these trivial instances.
--
-- instance HasServer API context where
--   type ServerT API m = ServerT API' m
--   route _ = route (Proxy :: Proxy API')
--
-- type instance IsElem' e API = IsElem e API'
--
-- server :: Server API
-- server = pure swaggerDoc
--     :\<|> 'swaggerUIServer'
--     :\<|> (pure "Hello World" :\<|> catEndpoint)
--   where
--     catEndpoint name = pure $ Cat name False
-- @

module Servant.Swagger.UI (
    -- * Swagger UI API
    SwaggerUI,
    swaggerUIServer,
    -- * Internals
    SwaggerUiHtml(..),
    ) where

import Data.ByteString                (ByteString)
import Data.FileEmbed                 (embedStringFile)
import Data.Monoid                    ((<>))
import GHC.TypeLits                   (Symbol)
import Network.Wai.Application.Static (embeddedSettings, staticApp)
import Servant
import Servant.HTML.Blaze             (HTML)
import Text.Blaze                     (ToMarkup (..))
import Servant.Swagger.UI.Internal

import qualified Data.Text as T

-- | Swagger API ui.
type SwaggerUI (dir :: Symbol) endpoint api = dir :>
    ( Get '[HTML] (SwaggerUiHtml endpoint api) :<|>
     "index.html" :> Get '[HTML] (SwaggerUiHtml endpoint api) :<|>
     Raw)

-- | Index file for swagger ui.
--
-- It's configured by the location of swagger schema.
data SwaggerUiHtml endpoint api = SwaggerUiHtml

instance (IsElem endpoint api, HasLink endpoint, MkLink endpoint ~ URI)
    => ToMarkup (SwaggerUiHtml endpoint api) where
    toMarkup _ = preEscapedToMarkup $
        T.replace "SWAGGER_URL_PLACEHOLDER" url swaggerUiIndexTemplate
      where
        uri = safeLink (Proxy :: Proxy api) (Proxy :: Proxy endpoint) :: URI
        url = T.pack $ "/" <> uriPath uri -- TODO: do we need more?

-- | Serve Swagger UI on @/<dir>@ using @endpoint@ as Swagger spec source for @api@.
swaggerUIServer :: Server (SwaggerUI dir endpoint api)
swaggerUIServer = return SwaggerUiHtml :<|> return SwaggerUiHtml :<|> rest
  where rest = staticApp $ embeddedSettings swaggerUiFiles

swaggerUiIndexTemplate :: T.Text
swaggerUiIndexTemplate = $(embedStringFile "index.html.tmpl")

swaggerUiFiles :: [(FilePath, ByteString)]
swaggerUiFiles = $(mkRecursiveEmbedded "swagger-dist-2.1.4")
