#pragma once

/* Namespace **************************************************************************************/
namespace engine
{

/* Managed Declaration ****************************************************************************/
template<class T>
class Managed
{
public:
	// Constructor/Deconstructor
	Managed();
	virtual ~Managed();

	// Functions
	T *GetNext() const;
	void Activate();
	void Deactivate();

private:
	// Static Members
	static T *first;

	// Members
	T *prev, *next;
};

/* Managed Template Definition ********************************************************************/

// Static Members --------------------------------------------------------------
template<class T> T *Managed<T>::first = 0; 

// Constructor/Deconstructor ---------------------------------------------------

/*
** Constructs a Managed<T>.
*/
template<class T>
Managed<T>::Managed(const string &name)
	: prev(0)
	, next(0)
{
}

/*
** Deconstructs a Managed<T>.
*/
template<class T>
Managed<T>::~Managed()
{
}

// Functions -------------------------------------------------------------------

/*
** Returns the first instance of Managed<T>.
*/
template<class T>
T *Managed<T>::GetFirst()
{
	return first;
}

/*
** Returns the instance of Managed<T> after this.
*/
template<class T>
T *Managed<T>::GetNext() const
{
	return next;
}

/*
** Activates this Managed<T>.
*/
template<class T>
void Managed<T>::Enable()
{
	// Add to this Managed<T>'s active list
	T *oldFirst = first;
	first = (T *) this;

	if (oldFirst) {
		this->next = oldFirst;
		oldFirst->prev = (T *) this;
	}
}

/*
** Deactivates this Managed<T>.
*/
template<class T>
void Managed<T>::Disable()
{
	// Removes from this Managed<T>'s active list
	if (this->prev) {
		this->prev->next = this->next;

		if (this->next) {
			this->next->prev = this->prev;
		}

	} else {
		first = this->next;

		if (first) {
			first->prev = NULL;
		}
	}
}

} // namespace engine