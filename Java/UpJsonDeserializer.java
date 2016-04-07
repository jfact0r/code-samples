package com.edutect.up.api.jackson;

import java.io.IOException;
import java.util.Collections;
import java.util.Comparator;
import java.util.Iterator;
import java.util.List;

import org.apache.commons.beanutils.PropertyUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.cirrusaustralia.cub.ejb.UpEntity;
import com.cirrusaustralia.cub.ejb.enums.DETAIL;
import com.cirrusaustralia.up.ejb.sessions.ApiSessionRemote;
import com.edutect.up.api.ProxyEJB;
import com.fasterxml.jackson.core.JsonParser;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.BeanProperty;
import com.fasterxml.jackson.databind.DeserializationContext;
import com.fasterxml.jackson.databind.JsonDeserializer;
import com.fasterxml.jackson.databind.JsonMappingException;
import com.fasterxml.jackson.databind.deser.BeanDeserializer;
import com.fasterxml.jackson.databind.deser.BeanDeserializerBase;
import com.fasterxml.jackson.databind.deser.SettableBeanProperty;

/**
 * BeanDeserializer subclass with custom processing for <code>UpEntity</code>s.
 * Handles re-creating deleted entities, finding managed entities that match the
 * deserialized JSON and updating those entities.
 * 
 * @author Joel
 */
public class UpJsonDeserializer extends BeanDeserializer {

	private UpObjectMapper mapper;
	protected ApiSessionRemote apiSession = ProxyEJB.getInstance().getApiEJB();

	private static final Logger log = LoggerFactory.getLogger(UpJsonDeserializer.class);
	
	protected UpJsonDeserializer(BeanDeserializerBase src, UpObjectMapper mapper) {
		super(src);

		// Disable vanilla processing (as we'll need to do custom processing)
		this._vanillaProcessing = false;

		// Store our mapper
		this.mapper = mapper;
	}

	@Override
	public Object deserializeWithObjectId(JsonParser jp,
			DeserializationContext ctxt) throws IOException,
			JsonProcessingException {
		// Deserialize object and try to find its new/old obj in our maps
		UpEntity obj = (UpEntity) super.deserializeWithObjectId(jp, ctxt);
		UpEntity oldObj = (UpEntity) mapper.oldObjectMap.get(obj.getJsonId());
		UpEntity newObj = (UpEntity) mapper.newObjectMap.get(obj.getJsonId());

		// If we have no new/old obj yet, try to find our old obj with our ID
		if (newObj == null && oldObj == null && obj.getId() != 0) {
			oldObj = apiSession.find(obj.getClass(), obj.getId(), DETAIL.NONE);

			if (oldObj == null) {
				// Nothing matches this ID - get rid of it
				obj.setId(0);
			} else {
				// Found old object - add to our map
				mapper.oldObjectMap.put(obj.getJsonId(), oldObj);
			}
		}

		// If we have an old obj confirm we are allowed to update it
		if (mapper.getDelegate() != null) {
			if (oldObj != null
					&& !mapper.getDelegate().shouldUpdate(oldObj,
							jp.getParsingContext().getEntryCount() > 0)) {
				// Not allowed to update this old obj - just return it instead
				return oldObj;
			}
		}

		// Check if we have a new obj to update using our deserialized obj
		if (newObj == null) {
			// No new obj found - use our deserialized object as our new obj
			mapper.newObjectMap.put(obj.getJsonId(), obj);
			newObj = obj;
		}

		// Update our deserialized object
		try {
			// Copy properties from deserialized object to new obj
			Iterator<SettableBeanProperty> it = properties();
			while (it.hasNext()) {
				SettableBeanProperty prop = it.next();
				String name = prop.getName();

				// Only copy props we can write (and ignore the ID)
				if (PropertyUtils.isWriteable(newObj, name)
						&& PropertyUtils.isReadable(obj, name)
						&& !name.equals("id")) {
					Object value = PropertyUtils.getProperty(obj, name);

					// Sort lists of entities to move new objs to the end
					if (value instanceof List) {
						List<?> list = (List<?>) value;
						if (list.size() > 1) {
							Collections.sort(list, new Comparator<Object>() {
								public int compare(Object e1, Object e2) {
									if (e1 instanceof UpEntity) {
										return ((UpEntity) e1).getId() > 0 ? -1
												: 1;
									}
									return 0;
								}
							});
						}
					}

					// Don't copy null values
					if (value != null) {
						PropertyUtils.setProperty(newObj, name, value);
					}
				}
			}
		} catch (Exception e) {
			log.error("Error deserializing", e);
		}

		return newObj;
	}

	@Override
	public JsonDeserializer<?> createContextual(DeserializationContext ctxt,
			BeanProperty property) throws JsonMappingException {
		JsonDeserializer<?> result = null;

		// Prevent errors for our memberless generated ID property (from mixin)
		if (property == null || property.getMember() != null) {
			result = super.createContextual(ctxt, property);
		}

		return result;
	}
}
