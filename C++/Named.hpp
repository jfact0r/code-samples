#pragma once

/// Named
///
/// Manages the assignment of names to unique ids for the template class. Each
/// named instance stores its associated name assignment (name, id). This
/// centralizes the storage of names and allows fast name to id conversions.

/* Includes ***************************************************************************************/
#include <string>
#include <map>

/* Using ******************************************************************************************/
using std::string;
using std::map;
using std::pair;

/* Namespace **************************************************************************************/
namespace engine
{

/* Types ******************************************************************************************/
typedef map<const string, unsigned int> NameAssignmentMap;
typedef pair<const string, unsigned int> NameAssignment;

/* Named Declaration ******************************************************************************/
template<class T>
class Named
{
public:
	// Constructor/Deconstructor
	Named(const string &name);
	virtual ~Named();

	// Functions
	inline const string &GetName() const { return nameAssignment.first; }
	inline const unsigned int &GetId() const { return nameAssignment.second; }

	// Static Functions
	static NameAssignment &GetNameAssignment(const string &name);
	static NameAssignment *FindNameAssignment(const string &name);
	static bool IsNameAssigned(const string &name);

private:
	// Members
	const NameAssignment &nameAssignment;

	// Static Members
	static NameAssignmentMap nameAssignmentMap;
	static unsigned int nextId;
};

/* Comp Template Definition ******************************************************************/

// Static Members --------------------------------------------------------------
template<class T> NameAssignmentMap Named<T>::nameAssignmentMap;
template<class T> unsigned int Named<T>::nextId = 0;

// Constructor/Deconstructor ---------------------------------------------------
template<class T>
Named<T>::Named(const string &name)
	: nameAssignment(GetNameAssignment(name))
{
}

template<class T>
Named<T>::~Named()
{
}

// Static Functions ------------------------------------------------------------

/*
** Returns a NameAssignment for the given name, creating one if it doesn't
** exist.
*/
template<class T>
NameAssignment &Named<T>::GetNameAssignment(const string &name)
{
	// Try to insert a new assignment
	pair<NameAssignmentMap::iterator, bool> result =
		nameAssignmentMap.insert(NameAssignment(name, int()));
	NameAssignment &assign = *result.first;

	// If it's a new assignment, initialize the id
	if (result.second) {
		assign.second = ++nextId;
	}

	// Return the assignment
	return assign;
}

/*
** Returns the NameAssignment for the given name or null if it doesn't exist.
*/
template<class T>
NameAssignment *Named<T>::FindNameAssignment(const string &name)
{
	NameAssignmentMap::iterator result = nameAssignmentMap.find(name);

	if (result != nameAssignmentMap.end()) {
		return &*result;
	}

	return NULL;
}

/*
** Returns whether or not the given name is assigned.
*/
template<class T>
bool Named<T>::IsNameAssigned(const string &name)
{
	return (nameAssignmentMap.find(name) == nameAssignmentMap.end());
}


} // namespace engine