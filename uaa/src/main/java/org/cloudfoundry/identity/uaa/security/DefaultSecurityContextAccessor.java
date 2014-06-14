/*
 * Copyright 2006-2011 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on
 * an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations under the License.
 */
package org.cloudfoundry.identity.uaa.security;

import org.cloudfoundry.identity.uaa.authentication.UaaPrincipal;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.provider.OAuth2Authentication;

/**
 * @author Luke Taylor
 * @author Dave Syer
 */
public class DefaultSecurityContextAccessor implements SecurityContextAccessor {

	@Override
	public boolean isClient() {
		Authentication a = SecurityContextHolder.getContext().getAuthentication();

		if (!(a instanceof OAuth2Authentication)) {
			throw new IllegalStateException("Must be an OAuth2Authentication to check if user is a client");
		}

		return ((OAuth2Authentication) a).isClientOnly();
	}

	@Override
	public boolean isAdmin() {
		Authentication a = SecurityContextHolder.getContext().getAuthentication();
		return AuthorityUtils.authorityListToSet(a.getAuthorities()).contains("ROLE_ADMIN");
	}

	@Override
	public String getUserId() {
		Authentication a = SecurityContextHolder.getContext().getAuthentication();
		return ((UaaPrincipal) a.getPrincipal()).getId();
	}

}
