/* Includes ***************************************************************************************/
#include "Entity.hpp"

/* Using ******************************************************************************************/
using std::string;
using std::map;
using std::ostream;
using std::endl;

/* Namespace **************************************************************************************/
namespace engine
{

/* Entity Definition ******************************************************************************/

// Constructor/Deconstructor ---------------------------------------------------

/*
** Constructs an Entity.
*/
Entity::Entity()
{
}

/*
** Deconstructs an Entity.
*/
Entity::~Entity()
{
	// Delete props
	for (PropMap::iterator it = props.begin(), ed = props.end(); it != ed; ++it) {
		delete it->second;
	}
	props.clear();

	// Delete comps
	for (CompMap::iterator it = comps.begin(), ed = comps.end(); it != ed; ++it) {
		delete it->second;
	}
	comps.clear();
}

// Functions -------------------------------------------------------------------

/*
** Adds a Comp.
*/
void Entity::AddComp(Comp *comp)
{
	// Get a reference to the existing component associated with the id of the new component
	Comp *&oldComp = comps[comp->GetId()];

	// Free that component if it's not the same as this one
	if (oldComp != comp) {
		delete oldComp;
	}

	// Set the reference to the new component
	oldComp = comp;

	// Setup the new component
	comp->Attach(this);
}

/*
** Attempts to find and return the Prop associated with the given name. A NULL pointer is returned
** if no association is found.
*/
Prop *Entity::FindProp(const string &name)
{
	// Try to find an assignment for the given name
	NameAssignment *nameAssignment = Prop::FindNameAssignment(name);

	if (nameAssignment != NULL) {
		// Try to find the property for the assignment
		PropIterator prop = props.find(nameAssignment->second);

		if (prop != props.end()) {
			return &*prop->second;
		}
	}

	return NULL;
}

/*
** Returns a reference to the Prop associated with the given name. If no association exists a new
** association is created and a reference to it is returned.
*/
Prop *&Entity::GetProp(const string &name)
{
	// Get the assignment for this name
	NameAssignment &nameAssignment = Prop::GetNameAssignment(name);

	// Get the property associated with the assignment
	return props[nameAssignment.second];
}

// Operators -------------------------------------------------------------------

/*
** Prints an Entity to a stream.
*/
ostream & operator<<(ostream &os, const Entity &e)
{
	// Print name
	os << "Entity" << endl;
	os << '{';

	// Print comps
	os << endl << "\tComponents:" << endl;

	for (Entity::CompIterator it = e.comps.begin(), ed = e.comps.end(); it != ed; ++it) {
		os << endl << "\t[" << it->first << "] " << *(it->second);
	}

	// Print props
	os << endl << endl << "\tProperties:" << endl;

	for (Entity::PropIterator it = e.props.begin(), ed = e.props.end(); it != ed; ++it) {
		os << endl << "\t[" << it->first << "] " << *(it->second);
	}

	os << endl;
	os << '}';

	return os;
}

} // namespace engine