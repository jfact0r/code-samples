package com.cirrusaustralia.cub.client.struts.actions;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;

import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.NameValuePair;
import org.apache.http.client.ClientProtocolException;
import org.apache.http.client.HttpClient;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.client.methods.HttpRequestBase;
import org.apache.http.impl.client.DefaultHttpClient;
import org.apache.http.message.BasicNameValuePair;
import org.apache.http.util.EntityUtils;
import org.apache.struts.action.ActionForm;
import org.apache.struts.action.ActionForward;
import org.apache.struts.action.ActionMapping;
import org.apache.struts.action.ActionMessage;
import org.apache.struts.action.ActionMessages;
import org.json.simple.JSONObject;
import org.json.simple.parser.JSONParser;
import org.json.simple.parser.ParseException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.cirrusaustralia.cub.ejb.Audit;
import com.edutect.oauth.OAuthConstants;
import com.ibm.websphere.security.WSSecurityHelper;

/**
 * Handles the response from an OAuth partner.
 * 
 * @version 1.0
 * @author Joel
 */
public class OAuthCallbackAction extends UnitPlannerLoginAction implements
		OAuthConstants {

	private static final Logger log = LoggerFactory.getLogger(OAuthCallbackAction.class);

	private static final String GOOGLE_APIS_URL = "https://www.googleapis.com/oauth2/";

	private static final String FWD_FAILURE = "failure";

	@Override
	public ActionForward execute(ActionMapping mapping, ActionForm form,
			HttpServletRequest request, HttpServletResponse response)
			throws Exception {
		// Check for an error
		if (request.getParameter("error") != null) {
			log.error("Error: " + request.getParameter("error"));

			ActionMessages errors = new ActionMessages();
			errors.add("error", new ActionMessage("login.error.unknown"));
			saveErrors(request, errors);
			return mapping.findForward(FWD_FAILURE);
		}

		// Get code
		String code = request.getParameter("code");

		// Get access token using code
		Map<String, String> params = new HashMap<String, String>();
		params.put("code", code);
		params.put("client_id", GOOGLE_CLIENT_ID);
		params.put("client_secret", GOOGLE_CLIENT_SECRET);
		params.put("redirect_uri", request.getRequestURL().substring(0,
				request.getRequestURL().indexOf(request.getRequestURI()))
				+ GOOGLE_CALLBACK_PATH);
		params.put("grant_type", "authorization_code");

		String json = post(GOOGLE_OAUTH2_URL + "token", params);

		JSONObject jsonObject = null;
		try {
			jsonObject = (JSONObject) new JSONParser().parse(json);
		} catch (ParseException e) {
			throw new RuntimeException("Unable to parse json " + json);
		}

		String accessToken = (String) jsonObject.get("access_token");
		request.setAttribute("access_token", accessToken);

		// Get info about the user using access token
		json = get(new StringBuilder(GOOGLE_APIS_URL
				+ "v1/userinfo?access_token=").append(accessToken).toString());

		try {
			jsonObject = (JSONObject) new JSONParser().parse(json);
		} catch (ParseException e) {
			throw new RuntimeException("Unable to parse json " + json);
		}

		// Get username
		String username = jsonObject.get("email").toString();

		// Try UP login
		ActionForward af = getUnitPlannerSession(username, request
				.getParameter("unitid"), mapping, request, null);

		// Check if the UP login was successful
		ActionMessages am = getErrors(request);
		if (am.size() > 0) {
			// UP login failed - revoke authentication
			ActionMessage msg = (ActionMessage) am.get().next();
			log.info("OAuth Login failed for user <" + username
					+ "> with error=" + msg.toString());
			WSSecurityHelper.revokeSSOCookies(request, response);
			request.getSession().invalidate();
		}

		// Done
		return af;
	}

	private String get(String url) throws ClientProtocolException, IOException {
		return execute(new HttpGet(url));
	}

	private String post(String url, Map<String, String> formParameters)
			throws ClientProtocolException, IOException {
		HttpPost request = new HttpPost(url);

		List<NameValuePair> nvps = new ArrayList<NameValuePair>();

		for (String key : formParameters.keySet()) {
			nvps.add(new BasicNameValuePair(key, formParameters.get(key)));
		}

		request.setEntity(new UrlEncodedFormEntity(nvps));

		return execute(request);
	}

	private String execute(HttpRequestBase request)
			throws ClientProtocolException, IOException {
		HttpClient httpClient = new DefaultHttpClient();
		HttpResponse response = httpClient.execute(request);

		HttpEntity entity = response.getEntity();
		String body = EntityUtils.toString(entity);

		if (response.getStatusLine().getStatusCode() != 200) {
			throw new RuntimeException("Expected 200 but got "
					+ response.getStatusLine().getStatusCode() + ", with body "
					+ body);
		}

		return body;
	}
}
