package org.cloudfoundry.identity.uaa.authentication;

import java.io.Serializable;
import java.util.Collection;
import java.util.List;

import org.springframework.security.core.Authentication;
import org.springframework.security.core.GrantedAuthority;

/**
 * Authentication token which represents a successfully authenticated user.
 *
 * @author Luke Taylor
 */
public class UaaAuthentication implements Authentication, Serializable {
	private List<? extends GrantedAuthority> authorities;
	private final UaaPrincipal principal;
	private final UaaAuthenticationDetails details;

	/**
	 * Creates a token with the supplied array of authorities.
	 *
	 * @param authorities the collection of <tt>GrantedAuthority</tt>s for the
	 *                    principal represented by this authentication object.
	 */
	public UaaAuthentication(UaaPrincipal principal, List<? extends GrantedAuthority> authorities, UaaAuthenticationDetails details) {
		if (principal == null || authorities == null) {
			throw new IllegalArgumentException("principal and authorities must not be null");
		}
		this.principal = principal;
		this.authorities = authorities;
		this.details = details;
	}

	@Override
	public String getName() {
		// TODO: Should we return the ID for the princpal name?
		return principal.getName();
	}

	@Override
	public Collection<? extends GrantedAuthority> getAuthorities() {
		return authorities;
	}

	@Override
	public Object getCredentials() {
		return null;
	}

	@Override
	public Object getDetails() {
		return details;
	}

	@Override
	public UaaPrincipal getPrincipal() {
		return principal;
	}

	@Override
	public boolean isAuthenticated() {
		return true;
	}

	@Override
	public void setAuthenticated(boolean isAuthenticated) {
		throw new UnsupportedOperationException();
	}

	@Override
	public boolean equals(Object o) {
		if (this == o) {
			return true;
		}
		if (o == null || getClass() != o.getClass()) {
			return false;
		}

		UaaAuthentication that = (UaaAuthentication) o;

		if (!authorities.equals(that.authorities)) {
			return false;
		}
		if (!principal.equals(that.principal)) {
			return false;
		}

		return true;
	}

	@Override
	public int hashCode() {
		int result = authorities.hashCode();
		result = 31 * result + principal.hashCode();
		return result;
	}
}
